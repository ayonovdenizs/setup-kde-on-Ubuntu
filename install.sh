sudo apt update
sudo apt full-upgrade
sudo apt install tasksel
sudo tasksel install kubuntu-full
sudo apt install xfce4 xfce4-goodies
sudo apt install tightvncserver
vncserver
vncserver -kill :1
mv ~/.vnc/xstartup ~/.vnc/xstartup.bak
wget https://raw.githubusercontent.com/AyonovDenizs/setuping435/ayden/xstartup
mv xstartup ~/.vnc/xstartup
sudo chmod +x ~/.vnc/xstartup
vncserver -localhost
