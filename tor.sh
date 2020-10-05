#!/bin/bash

if [ $(whoami) != "root" ]; then
    echo "Must be run as root"
    exit 1
fi

IPTABLES=$(which iptables)  # /sbin/iptables
OVPN=$(ip r | grep "wg" | awk '{print $3}')  # tun0
VPN_IP=$(ip r | grep "wg" | awk '{print $9}')  # 10.8.0.1
echo $OVPN
echo $VPN_IP

function route() {
    local arg=$1
    # Config IPtables to route all traffic trough Tor proxy
    # transparent Tor proxy
    $IPTABLES $arg INPUT -i $OVPN -s 10.0.0.0/24 -m state --state NEW -j ACCEPT
    $IPTABLES -t nat $arg PREROUTING -i $OVPN -p udp --dport 53 -s 10.0.0.0/24 -j DNAT --to-destination $VPN_IP:5353
    $IPTABLES -t nat $arg PREROUTING -i $OVPN -p tcp -s 10.0.0.0/24 -j DNAT --to-destination $VPN_IP:9040
    $IPTABLES -t nat $arg PREROUTING -i $OVPN -p udp -s 10.0.0.0/24 -j DNAT --to-destination $VPN_IP:9040

    ## Transproxy leak blocked:
    # https://trac.torproject.org/projects/tor/wiki/doc/TransparentProxy#WARNING
    $IPTABLES $arg OUTPUT -m conntrack --ctstate INVALID -j DROP
    $IPTABLES $arg OUTPUT -m state --state INVALID -j DROP
    $IPTABLES $arg OUTPUT ! -o lo ! -d 127.0.0.1 ! -s 127.0.0.1 -p tcp -m tcp --tcp-flags ACK,FIN ACK,FIN -j DROP
    $IPTABLES $arg OUTPUT ! -o lo ! -d 127.0.0.1 ! -s 127.0.0.1 -p tcp -m tcp --tcp-flags ACK,RST ACK,RST -j DROP
}

if ($IPTABLES --check INPUT -i $OVPN -s 10.0.0.0/24 -m state --state NEW -j ACCEPT 2>/dev/null); then
    echo "Stoping Tor and remove iptables routes"
    systemctl stop tor.service
    route "-D"
    cp ./torrc.bak /etc/tor/torrc
else
    echo "Starting Tor and adding iptables routes"
    cp /etc/tor/torrc ./torrc.bak
    cp ./torrc.new /etc/tor/torrc
    systemctl start tor.service
    sleep 3
    route "-A"
    echo "Now you can connect to your VPN and surf on the TOR network"
fi
