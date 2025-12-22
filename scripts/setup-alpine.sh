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
    dnsmasq-dnssec-nftset \
    nftables newt \
    wireguard-tools tailscale \
    ca-certificates curl wget python3

# 确保必要的信任锚点文件存在 (DNSSEC 依赖)
if [ ! -f /usr/share/dnsmasq/trust-anchors.conf ]; then
    apk add --no-cache dnsmasq-utils
fi

# enable routing service
rc-update add dnsmasq default
rc-update add nftables default

# 确保 sysctl 配置在启动时被应用
rc-update add sysctl default
# PPPoE preloading
echo "ppp_generic" >> /etc/modules
echo "pppoe" >> /etc/modules

# enable serial console
echo "ttyFIQ0::respawn:/sbin/agetty -L 1500000 ttyFIQ0 vt100" >> /etc/inittab
echo "ttyFIQ0" >> /etc/securetty

# root password
echo "root:joyo00088708" | chpasswd

echo "$(date +%Y%m%d)" > /etc/rom-version
[ -e /lib/firmware ] || mkdir -p /lib/firmware
[ -e /lib/modules ] || mkdir -p /lib/modules

# Set hostname
echo "alpine-router" > /etc/hostname
cat << 'EOL' > /etc/hosts
127.0.0.1       alpine.my.domain alpine localhost.localdomain localhost
::1             localhost localhost.localdomain
EOL

# Set up mirror
cat << 'EOL' > /etc/apk/repositories
http://mirrors.aliyun.com/alpine/v3.23/main
http://mirrors.aliyun.com/alpine/v3.23/community
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
    hostname alpine-router

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

setup-alpine -q -f /answer_file
rm -f /answer_file
