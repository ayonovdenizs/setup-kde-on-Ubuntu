clear
sudo apt update
clear
sudo apt full-upgrade
clear
sudo apt install tasksel
sudo tasksel install kubuntu-full
clear
sudo apt install xfce4 xfce4-goodies
sudo apt install tightvncserver
clear
vncserver
vncserver -kill :1
mv ~/.vnc/xstartup ~/.vnc/xstartup.bak
wget https://raw.githubusercontent.com/AyonovDenizs/setuping435/ayden/xstartup
mv xstartup ~/.vnc/xstartup
sudo chmod +x ~/.vnc/xstartup
vncserver -localhost
echo "успешно установлено."
echo "Successfully installed."

