#!/bin/bash

[ "$DEBUG" == "1" ] && set -x

set -e

if [ ! -d $OPENVPN_PATH/easy-rsa ]; then
   # Copy easy-rsa tools to /etc/openvpn
   rsync -avz /usr/share/easy-rsa $OPENVPN_PATH/

   # Configure easy-rsa vars file
   perl -p -i -e "s/export KEY_COUNTRY=.*/export KEY_COUNTRY=\"CA\"/g" $OPENVPN_PATH/easy-rsa/vars
   perl -p -i -e "s/export KEY_PROVINCE=.*/export KEY_PROVINCE=\"BARCELONA\"/g" $OPENVPN_PATH/easy-rsa/vars
   perl -p -i -e "s/export KEY_CITY=.*/export KEY_CITY=\"CASTELLDEFELS\"/g" $OPENVPN_PATH/easy-rsa/vars
   perl -p -i -e "s/export KEY_ORG=.*/export KEY_ORG=\"NIXEL\"/g" $OPENVPN_PATH/easy-rsa/vars
   perl -p -i -e "s/export KEY_EMAIL=.*/export KEY_EMAIL=\"manel\@nixelsolutions.com\"/g" $OPENVPN_PATH/easy-rsa/vars
   perl -p -i -e "s/export KEY_OU=.*/export KEY_OU=\"NIXEL\"/g" $OPENVPN_PATH/easy-rsa/vars

   pushd $OPENVPN_PATH/easy-rsa
   . ./vars
   ./clean-all
   ./build-ca --batch
   ./build-key-server --batch server
   ./build-dh
   ./build-key --batch RancherVPNClient
   openvpn --genkey --secret keys/ta.key
   popd
fi

# Update openvpn route
RANCHER_NETWORK_CIDR=`ip addr show dev eth0 | grep inet | grep 10.42 | awk '{print $2}' | xargs -i ipcalc -n {} | grep Network | awk '{print $2}' | awk -F/ '{print $1}'`
RANCHER_NETWORK_MASK=`ip addr show dev eth0 | grep inet | grep 10.42 | awk '{print $2}' | xargs -i ipcalc -n {} | grep Netmask | awk '{print $2}'`

# Create OpenVPN server config
cat > $OPENVPN_PATH/server.conf <<EOF
port 1194
proto udp
dev tun
keepalive 10 120
comp-lzo

user nobody
group nogroup

log-append $OPENVPN_PATH/openvpn.log
verb 3

persist-key
persist-tun

ca easy-rsa/keys/ca.crt
cert easy-rsa/keys/server.crt
key easy-rsa/keys/server.key
dh easy-rsa/keys/dh2048.pem
tls-auth easy-rsa/keys/ta.key 0

server 10.8.0.0 255.255.255.0
duplicate-cn

push "route $RANCHER_NETWORK_CIDR $RANCHER_NETWORK_MASK"
EOF

# Start openvpn server
openvpn --config $OPENVPN_PATH/server.conf
