#!/usr/bin/env bash
#
# install.sh — set up a KDE Plasma (or XFCE) desktop served over VNC on a
#              headless Ubuntu server.
#
# Usage:   sudo ./install.sh [options]
# Help:    ./install.sh --help
# Dry run: sudo ./install.sh --dry-run
#
# ---------------------------------------------------------------------------
set -Eeuo pipefail

# --- defaults --------------------------------------------------------------
readonly REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/AyonovDenizs/setup-kde-on-Ubuntu/ayden}"
readonly SUPPORTED_RELEASES="20.04 22.04 24.04 24.10 25.04"
readonly MIN_FREE_GB=5

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

DESKTOP="kde"                 # kde | kde-full | kubuntu-full | xfce
VNC_IMPL="auto"               # auto | tigervnc | tightvnc
DISPLAY_NUM="1"
GEOMETRY="1920x1080"
DEPTH="24"
LOCALHOST=1                   # 1 = listen on 127.0.0.1 only (use an SSH tunnel)
WITH_SYSTEMD=1
SKIP_UPGRADE=0
SET_PASSWORD=1
START_SESSION=1
DRY_RUN=0
ASSUME_YES=0
DO_UNINSTALL=0
TARGET_USER=""
XSTARTUP_URL="${XSTARTUP_URL:-$REPO_RAW_BASE/xstartup}"
UNIT_URL="${UNIT_URL:-$REPO_RAW_BASE/vncserver@.service}"

VNC_PKG=()
DESKTOP_PKGS=()
VNC_BIN="/usr/bin/vncserver"
TARGET_GROUP=""
TARGET_HOME=""
VNC_DIR=""

# --- pretty output ---------------------------------------------------------
if [[ -t 1 && "${NO_COLOR:-}" == "" ]]; then
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[36m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_OFF=""
fi

info()  { printf '%s\n' "${C_BLUE}==>${C_OFF} $*"; }
ok()    { printf '%s\n' "${C_GREEN}  ✔${C_OFF} $*"; }
warn()  { printf '%s\n' "${C_YELLOW}  !${C_OFF} $*" >&2; }
die()   { printf '%s\n' "${C_RED}  ✖ $*${C_OFF}" >&2; exit 1; }
step()  { printf '\n%s\n' "${C_BOLD}── $* ──${C_OFF}"; }
dry()   { printf '%s\n' "${C_YELLOW}  [dry-run]${C_OFF} $*"; }

on_error() {
    local rc=$? chain="${2:-top level}"
    chain="${chain%% main*}"                 # drop the repeated entry-point frames
    [[ -n "$chain" ]] || chain="top level"
    printf '\n%s\n' "${C_RED}✖ install.sh aborted (exit $rc) on line ${1:-?} in: ${chain// / -> }${C_OFF}" >&2
    printf '%s\n' "${C_RED}  failing command: ${3:-unknown}${C_OFF}" >&2
}
trap 'on_error $LINENO "${FUNCNAME[*]:-top level}" "$BASH_COMMAND"' ERR

# --- command wrappers ------------------------------------------------------
SUDO=()

run() {  # run <cmd...> — honours --dry-run
    if (( DRY_RUN )); then
        local cmd
        cmd="$(printf '%q ' "$@")"
        dry "${cmd% }"
        return 0
    fi
    "$@"
}

usage() {
    cat <<'EOF'
install.sh — install a KDE/XFCE desktop + VNC server on Ubuntu Server

Usage: sudo ./install.sh [options]

Desktop:
      --de NAME          kde (default, Plasma), kde-full (kubuntu-desktop),
                         kubuntu-full (full Kubuntu task) or xfce
      --skip-upgrade     do not run "apt full-upgrade" before installing

VNC server:
      --vnc NAME         tigervnc (default when available) or tightvnc
      --display N        display number of the session to enable (default: 1)
      --geometry WxH     virtual screen size (default: 1920x1080)
      --depth N          colour depth (default: 24)
      --no-localhost     listen on all interfaces instead of 127.0.0.1
                         (insecure — prefer an SSH tunnel)
      --no-password      do not set a VNC password now
      --no-start         install only, do not start the session

Service:
      --no-systemd       do not install/enable the systemd unit
      --user NAME        user that owns the VNC session
                         (default: $SUDO_USER, or the caller)

Misc:
      --uninstall        stop/disable the service and remove the unit file
      --dry-run          print every action without changing anything
  -y, --yes              do not ask for confirmation
  -h, --help             show this help

Environment:
      VNC_PASSWORD       set the VNC password non-interactively
      XSTARTUP_URL       override where xstartup is downloaded from
      UNIT_URL           override where the systemd template is downloaded from

Typical remote access (VNC stays on localhost):
      ssh -L 5901:localhost:5901 <user>@<server>   # then connect to localhost:5901
EOF
}

parse_args() {
    while (( $# )); do
        case "$1" in
            --de)            DESKTOP="${2:?--de needs a value}"; shift 2 ;;
            --de=*)          DESKTOP="${1#*=}"; shift ;;
            --vnc)           VNC_IMPL="${2:?--vnc needs a value}"; shift 2 ;;
            --vnc=*)         VNC_IMPL="${1#*=}"; shift ;;
            --display)       DISPLAY_NUM="${2:?--display needs a value}"; shift 2 ;;
            --display=*)     DISPLAY_NUM="${1#*=}"; shift ;;
            --geometry)      GEOMETRY="${2:?--geometry needs a value}"; shift 2 ;;
            --geometry=*)    GEOMETRY="${1#*=}"; shift ;;
            --depth)         DEPTH="${2:?--depth needs a value}"; shift 2 ;;
            --depth=*)       DEPTH="${1#*=}"; shift ;;
            --user)          TARGET_USER="${2:?--user needs a value}"; shift 2 ;;
            --user=*)        TARGET_USER="${1#*=}"; shift ;;
            --no-localhost)  LOCALHOST=0; shift ;;
            --no-systemd)    WITH_SYSTEMD=0; shift ;;
            --no-password)   SET_PASSWORD=0; shift ;;
            --no-start)      START_SESSION=0; shift ;;
            --skip-upgrade)  SKIP_UPGRADE=1; shift ;;
            --uninstall)     DO_UNINSTALL=1; shift ;;
            --dry-run)       DRY_RUN=1; shift ;;
            -y|--yes)        ASSUME_YES=1; shift ;;
            -h|--help)       usage; exit 0 ;;
            *)               usage >&2; die "unknown option: $1" ;;
        esac
    done

    [[ "$DISPLAY_NUM" =~ ^[0-9]+$ ]] || die "--display must be a number, got: $DISPLAY_NUM"
    (( DISPLAY_NUM > 0 ))            || die "--display must be greater than 0"
    [[ "$GEOMETRY" =~ ^[0-9]+x[0-9]+$ ]] || die "--geometry must look like 1920x1080, got: $GEOMETRY"
    [[ "$DEPTH" =~ ^(16|24|32)$ ]]   || die "--depth must be 16, 24 or 32, got: $DEPTH"

    case "$DESKTOP" in
        kde|kde-full|kubuntu-full|xfce) ;;
        *) die "--de must be one of: kde, kde-full, kubuntu-full, xfce (got: $DESKTOP)" ;;
    esac
    case "$VNC_IMPL" in
        auto|tigervnc|tightvnc) ;;
        *) die "--vnc must be one of: auto, tigervnc, tightvnc (got: $VNC_IMPL)" ;;
    esac
}

# --- preflight -------------------------------------------------------------
resolve_privileges() {
    if (( EUID == 0 )); then
        SUDO=()
    else
        command -v sudo >/dev/null 2>&1 || die "this script needs root: re-run with sudo"
        SUDO=(sudo)
    fi
}

resolve_target_user() {
    if [[ -z "$TARGET_USER" ]]; then
        if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
            TARGET_USER="$SUDO_USER"
        elif (( EUID != 0 )); then
            TARGET_USER="$(id -un)"
        else
            die "running as root: pass --user <name> of the account that will own the VNC session"
        fi
    fi

    id "$TARGET_USER" >/dev/null 2>&1 || die "no such user: $TARGET_USER"
    TARGET_GROUP="$(id -gn "$TARGET_USER")"
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || die "cannot determine a home directory for $TARGET_USER"
    VNC_DIR="$TARGET_HOME/.vnc"
}

# as_target <cmd...> — run a command as the session owner
as_target() {
    if (( EUID != 0 )) || [[ "$(id -un)" == "$TARGET_USER" ]]; then
        "$@"
        return
    fi
    if command -v runuser >/dev/null 2>&1; then
        runuser -u "$TARGET_USER" -- "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo -u "$TARGET_USER" -- "$@"
    else
        su -s /bin/bash "$TARGET_USER" -c "$(printf '%q ' "$@")"
    fi
}

check_os() {
    local id="" version=""
    # shellcheck source=/dev/null
    [[ -r /etc/os-release ]] && . /etc/os-release
    id="${ID:-unknown}"; version="${VERSION_ID:-unknown}"

    if [[ "$id" != "ubuntu" ]]; then
        warn "this script targets Ubuntu, but this is ${PRETTY_NAME:-$id}."
        (( DRY_RUN )) || warn "package names may differ — continuing anyway."
    elif [[ " $SUPPORTED_RELEASES " != *" $version "* ]]; then
        warn "Ubuntu $version is not in the tested list ($SUPPORTED_RELEASES)."
    else
        ok "Ubuntu $version detected"
    fi
}

check_disk_space() {
    local avail_gb
    avail_gb="$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')" || return 0
    [[ -n "$avail_gb" ]] || return 0
    if (( avail_gb < MIN_FREE_GB )); then
        warn "only ${avail_gb}G free on / — a Plasma install needs ~${MIN_FREE_GB}G or more."
    else
        ok "${avail_gb}G free on /"
    fi
}

resolve_packages() {
    case "$DESKTOP" in
        kde)         DESKTOP_PKGS=(kde-plasma-desktop) ;;
        kde-full)    DESKTOP_PKGS=(kubuntu-desktop) ;;
        kubuntu-full) DESKTOP_PKGS=(kubuntu-full) ;;
        xfce)        DESKTOP_PKGS=(xfce4 xfce4-goodies) ;;
    esac
    # dbus-x11: dbus-launch used by xstartup; x11-xserver-utils: xrdb; xfonts-base: core fonts
    DESKTOP_PKGS+=(dbus-x11 x11-xserver-utils xfonts-base xauth)

    if [[ "$VNC_IMPL" == "auto" ]]; then
        if apt-cache policy tigervnc-standalone-server 2>/dev/null | grep -q '^  Candidate: [0-9]'; then
            VNC_IMPL="tigervnc"
        else
            VNC_IMPL="tightvnc"
            warn "tigervnc-standalone-server not available — falling back to tightvncserver."
        fi
    fi

    case "$VNC_IMPL" in
        tigervnc) VNC_PKG=(tigervnc-standalone-server tigervnc-common) ;;
        tightvnc) VNC_PKG=(tightvncserver) ;;
    esac
}

preflight() {
    step "Preflight"
    resolve_privileges
    resolve_target_user
    check_os
    check_disk_space
    resolve_packages
    ok "desktop: $DESKTOP (${DESKTOP_PKGS[*]})"
    ok "vnc:     $VNC_IMPL (${VNC_PKG[*]})"
    ok "session: $TARGET_USER:$DISPLAY_NUM  ${GEOMETRY}x${DEPTH}  localhost=$LOCALHOST"
}

confirm() {  # confirm <question>
    (( ASSUME_YES || DRY_RUN )) && return 0
    [[ -t 0 ]] || return 0
    local answer
    read -r -p "$1 [y/N] " answer
    [[ "$answer" =~ ^[Yy] ]]
}

# --- installation steps ----------------------------------------------------
update_system() {
    step "Updating package lists"
    # env goes *after* sudo: sudo resets the environment by default
    run "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update -y
    if (( SKIP_UPGRADE )); then
        info "skipping apt full-upgrade (--skip-upgrade)"
    else
        run "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
    fi
}

apt_install() {  # apt_install <pkgs...>
    # no --no-install-recommends: the desktop metapackages rely on Recommends
    # for panels, fonts and artwork to end up usable
    run "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

install_desktop() {
    step "Installing the $DESKTOP desktop"
    apt_install "${DESKTOP_PKGS[@]}"
}

install_vnc() {
    step "Installing the $VNC_IMPL server"
    apt_install "${VNC_PKG[@]}"
    if (( ! DRY_RUN )); then
        command -v vncserver >/dev/null 2>&1 || die "vncserver was not installed"
        VNC_BIN="$(command -v vncserver)"
        ok "vncserver at $VNC_BIN ($(vncserver --version 2>&1 | head -1))"
    fi
}

fetch_to() {  # fetch_to <url> <dest>
    local url="$1" dest="$2"
    mkdir -p "$(dirname -- "$dest")"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$dest" "$url"
    else
        die "need curl or wget to download $url"
    fi
}

install_xstartup() {
    step "Configuring ~/.vnc for $TARGET_USER"
    local dest="$VNC_DIR/xstartup" local_copy="$SCRIPT_DIR/xstartup" tmp=""

    if (( DRY_RUN )); then
        dry "mkdir -p $VNC_DIR (mode 700, owner $TARGET_USER)"
        if [[ -s "$local_copy" ]]; then
            dry "install $local_copy -> $dest"
        else
            dry "download $XSTARTUP_URL -> $dest"
        fi
        return 0
    fi

    "${SUDO[@]}" install -d -o "$TARGET_USER" -g "$TARGET_GROUP" -m 700 "$VNC_DIR"

    if [[ -e "$dest" ]]; then
        local backup
        backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
        "${SUDO[@]}" mv "$dest" "$backup"
        info "previous xstartup kept as $(basename -- "$backup")"
    fi

    if [[ -s "$local_copy" ]]; then
        "${SUDO[@]}" install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 755 "$local_copy" "$dest"
        ok "installed xstartup from $local_copy"
    else
        tmp="$(mktemp)"
        fetch_to "$XSTARTUP_URL" "$tmp" || { rm -f "$tmp"; die "could not download $XSTARTUP_URL"; }
        head -1 "$tmp" | grep -q '^#!' || { rm -f "$tmp"; die "downloaded xstartup does not look like a script"; }
        "${SUDO[@]}" install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 755 "$tmp" "$dest"
        rm -f "$tmp"
        ok "installed xstartup from $XSTARTUP_URL"
    fi
}

set_vnc_password() {
    (( SET_PASSWORD )) || { info "skipping VNC password (--no-password)"; return 0; }

    if [[ -s "$VNC_DIR/passwd" ]]; then
        ok "VNC password already set ($VNC_DIR/passwd)"
        return 0
    fi

    if (( DRY_RUN )); then
        dry "vncpasswd (as $TARGET_USER)"
        return 0
    fi

    if [[ -n "${VNC_PASSWORD:-}" ]]; then
        printf '%s\n%s\nn\n' "$VNC_PASSWORD" "$VNC_PASSWORD" | as_target vncpasswd >/dev/null
        ok "VNC password set from \$VNC_PASSWORD"
    elif [[ -t 0 ]]; then
        info "set the VNC password for $TARGET_USER (view-only password: answer 'n')"
        as_target vncpasswd
    else
        warn "no TTY and no \$VNC_PASSWORD — run 'vncpasswd' as $TARGET_USER before connecting"
    fi
}

# --- systemd unit ----------------------------------------------------------
get_unit_template() {  # prints the template on stdout
    local local_copy="$SCRIPT_DIR/vncserver@.service"
    if [[ -s "$local_copy" ]]; then
        cat -- "$local_copy"
    else
        fetch_to "$UNIT_URL" /dev/stdout
    fi
}

render_unit() {
    local localhost_flag=""
    if (( LOCALHOST )); then localhost_flag="-localhost"; fi

    sed -e "s|@USER@|$TARGET_USER|g" \
        -e "s|@GROUP@|$TARGET_GROUP|g" \
        -e "s|@HOME@|$TARGET_HOME|g" \
        -e "s|@VNC_BIN@|$VNC_BIN|g" \
        -e "s|@GEOMETRY@|$GEOMETRY|g" \
        -e "s|@DEPTH@|$DEPTH|g" \
        -e "s|@LOCALHOST@|$localhost_flag|g" \
        -e '/^Exec/s|  *| |g'   # tidy the gap left by an empty @LOCALHOST@
}

install_service() {
    if (( ! WITH_SYSTEMD )); then
        info "skipping the systemd unit (--no-systemd)"
        return 0
    fi

    step "Installing the systemd service (vncserver@.service)"
    local unit="/etc/systemd/system/vncserver@.service" rendered
    rendered="$(get_unit_template | render_unit)"
    grep -q '@[A-Z_]*@' <<<"$rendered" && die "unit template still has unsubstituted placeholders"

    if (( DRY_RUN )); then
        printf '%s\n' "$rendered" | sed 's/^/  | /'
        dry "write $unit; systemctl daemon-reload; systemctl enable vncserver@$DISPLAY_NUM"
        return 0
    fi

    printf '%s\n' "$rendered" | "${SUDO[@]}" tee "$unit" >/dev/null
    "${SUDO[@]}" systemctl daemon-reload
    ok "wrote $unit"
}

start_session() {
    (( START_SESSION )) || { info "not starting the session (--no-start)"; return 0; }

    step "Starting the VNC session on :$DISPLAY_NUM"
    if (( WITH_SYSTEMD )); then
        run "${SUDO[@]}" systemctl enable --now "vncserver@$DISPLAY_NUM.service"
    else
        local localhost_flag=()
        if (( LOCALHOST )); then localhost_flag=(-localhost); fi
        run as_target vncserver -depth "$DEPTH" -geometry "$GEOMETRY" \
            ${localhost_flag[@]+"${localhost_flag[@]}"} ":$DISPLAY_NUM"
    fi
}

verify() {
    if (( DRY_RUN )); then return 0; fi
    step "Verifying"
    local port=$(( 5900 + DISPLAY_NUM )) status="unknown"

    if (( WITH_SYSTEMD )); then
        status="$("${SUDO[@]}" systemctl is-active "vncserver@$DISPLAY_NUM.service" 2>/dev/null | tail -n1 || true)"
        if [[ "$status" == "active" ]]; then
            ok "vncserver@$DISPLAY_NUM.service is active"
        else
            warn "vncserver@$DISPLAY_NUM.service is '$status' — see: journalctl -u vncserver@$DISPLAY_NUM -e"
        fi
    fi

    sleep 2
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
        ok "listening on port $port (display :$DISPLAY_NUM)"
    else
        warn "nothing is listening on port $port yet — check $VNC_DIR/*.log"
    fi
}

print_summary() {
    step "Done"
    local port=$(( 5900 + DISPLAY_NUM ))
    printf '  Desktop session for %s%s%s on display :%s (port %s).\n\n' \
        "$C_BOLD" "$TARGET_USER" "$C_OFF" "$DISPLAY_NUM" "$port"

    if (( WITH_SYSTEMD )); then
        cat <<EOF
  Manage the service:
    sudo systemctl status  vncserver@$DISPLAY_NUM
    sudo systemctl restart vncserver@$DISPLAY_NUM
    sudo systemctl disable --now vncserver@$DISPLAY_NUM

EOF
    else
        cat <<EOF
  Start/stop it manually as $TARGET_USER:
    vncserver -depth $DEPTH -geometry $GEOMETRY :$DISPLAY_NUM
    vncserver -kill :$DISPLAY_NUM

EOF
    fi

    cat <<EOF
  Connect (the session listens on localhost only by default):
    ssh -L $port:localhost:$port $TARGET_USER@<this-host>
    then point a VNC viewer at localhost:$port
EOF
}

# --- uninstall -------------------------------------------------------------
uninstall() {
    step "Uninstalling the VNC service"
    local unit="/etc/systemd/system/vncserver@.service"
    if [[ ! -e "$unit" ]]; then
        info "$unit not found — nothing to do"
        return 0
    fi
    confirm "Stop and remove $unit?" || die "aborted by user"

    run "${SUDO[@]}" systemctl disable --now 'vncserver@*' 2>/dev/null || true
    run "${SUDO[@]}" rm -f "$unit"
    run "${SUDO[@]}" systemctl daemon-reload
    info "desktop/VNC packages were left installed; remove them with:"
    printf '    sudo apt-get purge %s %s\n' "${DESKTOP_PKGS[*]:-kde-plasma-desktop}" "${VNC_PKG[*]:-tigervnc-standalone-server}"
}

# --- entry point -----------------------------------------------------------
main() {
    parse_args "$@"

    printf '%s\n' "${C_BOLD}setup-kde-on-Ubuntu${C_OFF} — KDE/XFCE + VNC installer"
    (( DRY_RUN )) && info "dry run: nothing will be changed"

    if (( DO_UNINSTALL )); then
        resolve_privileges
        resolve_target_user
        uninstall
        exit 0
    fi

    preflight
    update_system
    install_desktop
    install_vnc
    install_xstartup
    set_vnc_password
    install_service
    start_session
    verify
    print_summary
}

main "$@"
