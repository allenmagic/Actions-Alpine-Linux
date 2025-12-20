#!/bin/sh
export LANG="en_US.UTF-8"
export LANGUAGE=en_US:en
export LC_NUMERIC="C"
export LC_CTYPE="C"
export LC_MESSAGES="C"
export LC_ALL="C"

apk update
apk add --no-cache openrc bash
apk add --no-cache alpine-base
apk add --no-cache util-linux
rc-update add bootmisc boot
rc-update add syslog default
rc-update add crond default

# enable ssh server
apk add --no-cache openssh
rc-update add sshd default
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# enable routing needed packages
apk add --no-cache \
    ppp ppp-pppoe ppp-openrc \
    dnsmasq \
    nftables \
    wireguard-tools tailscale \
    ca-certificates curl wget python3
    
# Create default folder path
mkdir -p /etc/dnsmasq.d
mkdir -p /etc/nftables.d
mkdir -p /usr/local/bin

# enable net forward
cat << 'EOL' >> /etc/sysctl.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.netfilter.nf_conntrack_max = 65535
EOL

# enable routing service
rc-update add dnsmasq default
rc-update add nftables default
# PPPoE preloading
echo "ppp_generic" >> /etc/modules
echo "pppoe" >> /etc/modules

# enable serial console
echo "ttyFIQ0::respawn:/sbin/agetty -L 1500000 ttyFIQ0 vt100" >> /etc/inittab
echo "ttyFIQ0" >> /etc/securetty

# root password
echo "root:fa" | chpasswd

echo "$(date +%Y%m%d)" > /etc/rom-version
[ -e /lib/firmware ] || mkdir -p /lib/firmware
[ -e /lib/modules ] || mkdir -p /lib/modules

# Set hostname
echo "alpine" > /etc/hostname
cat << 'EOL' > /etc/hosts
127.0.0.1       alpine.my.domain alpine localhost.localdomain localhost
::1             localhost localhost.localdomain
EOL

# Set up mirror
cat << 'EOL' > /etc/apk/repositories
http://mirrors.aliyun.com/alpine/v3.22/main
http://mirrors.aliyun.com/alpine/v3.22/community
EOL

# run setup-alpine quick mode
cat << 'EOL' > /answer_file
# Use US layout with US variant
KEYMAPOPTS="us us"

# Contents of /etc/network/interfaces
INTERFACESOPTS="auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    hostname alpine

auto eth1
iface eth1 inet static
    address 192.168.8.1
    netmask 255.255.255.0
"

# Set timezone to UTC
TIMEZONEOPTS="-z UTC"

# Add a random mirror
APKREPOSOPTS="-r"

# Install Openssh
SSHDOPTS="-c openssh"

# Use openntpd
NTPOPTS="-c openntpd"
EOL

# initial vars
cat << 'EOL' > /etc/nftables.d/vars.nft
define WAN = eth0
define LAN = eth1
EOL

# add nftables.conf
cat << 'EOL' > /etc/nftables.conf
#!/usr/sbin/nft -f
flush ruleset

# 引用变量
include "/etc/nftables.d/vars.nft"

table inet fw4 {
    # 这里的集合供后续模块使用
    set proxy_set { type ipv4_addr; flags interval; }
    set black_list { type ipv4_addr; flags dynamic, timeout; timeout 24h; }

    # 自动加载目录下所有模块
    include "/etc/nftables.d/*.nft"
}
EOL

setup-alpine -q -f /answer_file
rm -f /answer_file
