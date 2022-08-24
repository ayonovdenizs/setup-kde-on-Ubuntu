sudo apt update
sudo apt full-upgrade
sudo apt install tasksel
sudo tasksel install kubuntu-full
sudo apt install xfce4 xfce4-goodies
sudo apt install tightvncserver
vncserver
vncserver -kill :1
mv ~/.vnc/xstartup ~/.vnc/xstartup.bak
wget htt