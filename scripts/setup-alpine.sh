#!/bin/sh
# 注意：构建环境建议保留 C 编码以防路径解析出错，但镜像系统内部我们会设为中文
export LANG="en_US.UTF-8"
export LANGUAGE=en_US:en
export LC_ALL="C"

apk update
apk add --no-cache openrc bash alpine-base util-linux

# --- 中文支持包 ---
apk add --no-cache musl-locales musl-locales-lang tzdata

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
127.0.0.1       alpine-router alpine localhost.localdomain localhost
::1             localhost localhost.localdomain
EOL

# Set up mirror (固定使用阿里云，避免 setup-alpine 随机选择)
cat << 'EOL' > /etc/apk/repositories
http://mirrors.aliyun.com/alpine/v3.23/main
http://mirrors.aliyun.com/alpine/v3.23/community
EOL

# --- 设置全局中文环境变量 ---
cat << 'EOF' > /etc/profile.d/locale.sh
export LANG="zh_CN.UTF-8"
export LANGUAGE="zh_CN:zh"
export LC_ALL="zh_CN.UTF-8"
EOF
chmod +x /etc/profile.d/locale.sh

# run setup-alpine quick mode
cat << 'EOL' > /answer_file
# Use US layout
KEYMAPOPTS="us us"

# Network config
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

# 修改点：设置上海时区
TIMEZONEOPTS="-z Asia/Shanghai"

# 修改点：既然前面手动写了 repositories，这里设为 none 避免覆盖
# APKREPOSOPTS="none"

# SSH 和 NTP
SSHDOPTS="-c openssh"
NTPOPTS="-c openntpd"
EOL

# 执行安装配置
setup-alpine -q -f /answer_file
rm -f /answer_file
