#!/bin/sh
# To mark this file as executable:
# sudo cmhmod +x <thisfile.sh>
# To execute this file:
# ./<thisfile.sh>

echo "Global Protect Installer on Raspbian"

DHCP_RANGE=10.3.141.2,10.3.141.2
DHCP_SUBNET=255.255.255.252
GATEWAY_IP=10.3.141.1/30
#DHCP_DNS=10.3.141.1,8.8.8.8

#install openconnect, dnsmasq
sudo apt-get update
sudo apt-get install -y openconnect dnsmasq
sudo systemctl stop dnsmasq

#credentials
read -p "Enter your username: " USERNAME
read -s -p "Enter your password: " PASSWORD
read -p "Enter your server: " SERVER
read -p "Enter DNS IPs (separated by comma): " DHCP_DNS

echo ${PASSWORD} | sudo openconnect --protocol=gp ${SERVER} --user=${USERNAME} --passwd-on-stdin

read -p "Enter server certificate [pin-*]: " CERTIFICATE


# put at the end of the file
cat << _EOF_ | sudo tee -a /etc/dhcpcd.conf
interface eth0
	static ip_address=${GATEWAY_IP}
_EOF_

### DNSMASQ CONFIGURATION

sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig

# paste in the file
cat << _EOF_ | sudo tee -a /etc/dnsmasq.conf
no-resolv
interface=eth0
domain-needed
dhcp-range=${DHCP_RANGE},${DHCP_SUBNET},12h
dhcp-option=6,${DHCP_DNS}

_EOF_

# clear iptables
sudo iptables -F
sudo iptables -t nat -F

# enable forwarding
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sudo sysctl -w net.ipv4.ip_forward=1

#Loopback services
sudo iptables -A INPUT -i lo -m comment --comment "loopback" -j ACCEPT
sudo iptables -A OUTPUT -o lo -m comment --comment "loopback" -j ACCEPT

#Kill switch
Wsudo iptables -A FORWARD -i eth0 -o tun+ -m comment --comment "LAN out to VPN" -j ACCEPT

#Forward all to tun0
sudo iptables -t nat -A POSTROUTING -o tun+ -j MASQUERADE

# make iptables persistent
sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"

# backup original rc.local
sudo cp /etc/rc.local /etc/rc.local.orig
# add this just above "exit 0"
sudo sed -i 's/exit 0/# exit 0/g' /etc/rc.local
cat << _EOF_ | sudo tee -a /etc/rc.local
# Restoration of iptables
iptables-restore < /etc/iptables.ipv4.nat
# Autoconnect GlobalProtect
echo ${PASSWORD} | sudo openconnect --protocol=gp ${SERVER} --user=${USERNAME} --passwd-on-stdin --servercert ${CERTIFICATE} --reconnect-timeout 300
exit 0
_EOF_

sudo systemctl start dnsmasq
sudo reboot


