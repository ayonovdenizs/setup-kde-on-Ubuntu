# setup-kde-on-Ubuntu

Installs a **KDE Plasma** (or XFCE) desktop plus a **VNC server** on a headless
Ubuntu server, and wires it up as a systemd service that survives reboots.

Устанавливает **KDE Plasma** (или XFCE) и **VNC-сервер** на Ubuntu-сервер без
графики и настраивает автозапуск через systemd.

## Files / Файлы

| File | Purpose |
| --- | --- |
| `install.sh` | the installer — run this one |
| `xstartup` | session startup script, copied to `~/.vnc/xstartup` |
| `vncserver@.service` | systemd template rendered by the installer |

## Requirements / Требования

* Ubuntu Server 20.04 / 22.04 / 24.04 (other releases work, untested)
* root or sudo
* ~5 GB free disk space for a Plasma desktop

## Quick start / Быстрый старт

```bash
git clone https://github.com/AyonovDenizs/setup-kde-on-Ubuntu.git
cd setup-kde-on-Ubuntu
sudo ./install.sh                       # KDE Plasma + TigerVNC on :1
```

See everything the script would do first, without touching the system:

```bash
sudo ./install.sh --dry-run
```

### Options / Опции

```
--de kde|kde-full|kubuntu-full|xfce   desktop to install (default: kde)
--vnc tigervnc|tightvnc|auto          VNC server (default: auto -> TigerVNC)
--display N                           display number to enable (default: 1)
--geometry WxH                        virtual screen (default: 1920x1080)
--depth 16|24|32                      colour depth (default: 24)
--user NAME                           account owning the VNC session
--no-localhost                        listen on all interfaces (insecure)
--no-systemd                          install without the systemd unit
--no-start / --no-password            skip starting / skip setting a password
--skip-upgrade                        do not run "apt full-upgrade"
--uninstall                           stop + remove the systemd unit
-y, --help                            assume yes / show help
```

Environment: `VNC_PASSWORD` (non-interactive password), `XSTARTUP_URL`,
`UNIT_URL`.

Examples / Примеры:

```bash
sudo ./install.sh --de xfce --geometry 1600x900       # lighter desktop
sudo ./install.sh --de kubuntu-full --display 2       # full Kubuntu on :2
sudo VNC_PASSWORD='s3cret' ./install.sh --no-start    # unattended
```

## Connecting / Подключение

The session listens on `127.0.0.1` only, so reach it through an SSH tunnel:

Сессия слушает только `127.0.0.1`, поэтому подключайтесь через SSH-туннель:

```bash
ssh -L 5901:localhost:5901 <user>@<server>
# then point any VNC viewer at localhost:5901
```

Service management / Управление службой:

```bash
sudo systemctl status  vncserver@1
sudo systemctl restart vncserver@1
sudo systemctl disable --now vncserver@1     # stop and stop on boot
tail -f ~/.vnc/*.log                         # session log
```

## Uninstall / Удаление

```bash
sudo ./install.sh --uninstall                # removes the systemd unit
sudo apt-get purge kde-plasma-desktop tigervnc-standalone-server
sudo apt-get autoremove
```

## What changed vs. the original script / Что изменилось

* `set -Eeuo pipefail`, argument validation and a failure trap instead of a
  bare list of commands — the old script kept going after any error.
* Non-interactive apt (`DEBIAN_FRONTEND=noninteractive`, `-y`), so it no longer
  stalls on prompts.
* Actually starts **KDE**: the old script installed `kubuntu-full` *and* XFCE,
  then launched `startxfce4`. `xstartup` now detects Plasma
  (`startplasma-x11` → `startkde`) and only falls back to XFCE.
* `xstartup` uses `exec`, so the VNC server no longer tears the session down
  when the script returns.
* TigerVNC by default (TightVNC is unmaintained and missing on some newer
  releases), with automatic fallback to `tightvncserver`.
* The systemd unit no longer hardcodes the `ubuntu` user and no longer passes
  shell redirections (`> /dev/null 2>&1`) to `vncserver` — systemd hands those
  to the binary as arguments. It also restarts on failure.
* Timestamped `xstartup` backups, correct file ownership (`chown`, not
  `sudo chmod` on a root-owned file) and no files dropped into the current
  directory.
* `--dry-run`, `--uninstall`, a verification step and a printed summary with
  the exact SSH tunnel command.
* The stale duplicate of the unit file (`install`, byte-identical to
  `vncserver@.service`) was removed.
* `install.sh` and `xstartup` are stored executable (mode 755); they were 644,
  so a fresh clone could not run `./install.sh` without `chmod +x`.
