#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# R3S 网口定义 (eth0:靠近电源, eth1:靠近USB)
WAN_IF="eth0"
LAN_IF="eth1"

echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}      Alpine Router 网络初始化与自诊断工具    ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo "1) 光猫拨号模式 (二级路由 - WAN口自动获取IP)"
echo "2) 桥接拨号模式 (主路由 - Alpine 进行 PPPoE 拨号)"
read -p "请选择上网模式 [1-2]: " mode

# 函数：更新 nftables 变量
update_nft_vars() {
    mkdir -p /etc/nftables.d
    cat <<EOF > /etc/nftables.d/vars.nft
define WAN = $1
define LAN = $LAN_IF
EOF
    echo -e "${GREEN}[配置] nftables 变量已更新: WAN=$1${NC}"
}

# 函数：网络连通性检测 (在模式设置完成后调用)
check_online() {
    echo -e "${YELLOW}正在验证互联网连接 (Ping 223.5.5.5)...${NC}"
    # 给系统 3 秒时间更新路由表
    sleep 3
    if ping -c 3 -W 5 223.5.5.5 > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# --- 模式 1: DHCP 模式 ---
if [ "$mode" == "1" ]; then
    echo -e "${YELLOW}正在配置 DHCP 模式...${NC}"
    
    # 覆盖写入 interfaces
    cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto $WAN_IF
iface $WAN_IF inet dhcp
    hostname alpine

auto $LAN_IF
iface $LAN_IF inet static
    address 192.168.8.1
    netmask 255.255.255.0
EOF

    update_nft_vars "$WAN_IF"
    
    # 彻底停止拨号相关服务
    rc-service ppp.wan stop >/dev/null 2>&1
    rc-update del ppp.wan default >/dev/null 2>&1
    killall pppd >/dev/null 2>&1
    
    echo -e "${YELLOW}重启网络服务中...${NC}"
    rc-service networking restart
    
    # 【时机点】网络重启后执行检查
    if check_online; then
        echo -e "${GREEN}[成功] 光猫拨号模式配置完成，已联网！${NC}"
    else
        echo -e "${RED}[失败] 无法获取 IP 或无法访问外网，请检查与光猫的连线。${NC}"
    fi

# --- 模式 2: PPPoE 模式 ---
elif [ "$mode" == "2" ]; then
    while [ -z "$ppp_user" ]; do read -p "请输入拨号账号: " ppp_user; done
    while [ -z "$ppp_pass" ]; do read -s -p "请输入拨号密码: " ppp_pass; echo ""; done

    echo -e "${YELLOW}正在配置 PPPoE 拨号模式...${NC}"

    cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto $WAN_IF
iface $WAN_IF inet manual
    pre-up ip link set dev $WAN_IF up

auto $LAN_IF
iface $LAN_IF inet static
    address 192.168.8.1
    netmask 255.255.255.0
EOF

    cat <<EOF > /etc/ppp/chap-secrets
"$ppp_user" * "$ppp_pass"
EOF
    cp /etc/ppp/chap-secrets /etc/ppp/pap-secrets

    cat <<EOF > /etc/ppp/peers/wan
plugin rp-pppoe.so $WAN_IF
user "$ppp_user"
persist
maxfail 0
holdoff 5
defaultroute
usepeerdns
noauth
nodeflate
nobsdcomp
unit 0
EOF

    update_nft_vars "ppp0"
    
    # 启动拨号
    rc-update add ppp.wan default >/dev/null 2>&1
    echo -e "${YELLOW}重启网络并尝试拨号...${NC}"
    rc-service networking restart
    # 确保没有旧进程残留
    killall pppd >/dev/null 2>&1
    rc-service ppp.wan restart

    # 拨号状态循环检测
    echo -e "${YELLOW}等待运营商分配 IP (最多 30 秒)...${NC}"
    SUCCESS=0
    for i in {1..15}; do
        if ip addr show ppp0 > /dev/null 2>&1; then
            WAN_IP=$(ip addr show ppp0 | grep "inet " | awk '{print $2}')
            echo -e "${GREEN}[成功] 拨号已建立！获取到 IP: $WAN_IP${NC}"
            SUCCESS=1
            break
        fi
        echo -n "."
        sleep 2
    done

    # 【时机点】拨号成功后执行检查
    if [ $SUCCESS -eq 1 ]; then
        if check_online; then
            echo -e "${GREEN}[验证] 互联网访问正常！${NC}"
        else
            echo -e "${RED}[异常] 拨号成功但 Ping 不通，请检查 nftables 规则或 DNS。${NC}"
        fi
    else
        echo -e "${RED}\n[错误] 拨号失败！${NC}"
        echo -e "${YELLOW}拨号日志摘要:${NC}"
        logread | grep pppd | tail -n 5
    fi
else
    echo "无效选择。"
    exit 1
fi

echo -e "${GREEN}==============================================${NC}"
echo -e "${YELLOW}请确认上网正常后，执行 '${GREEN}lbu commit -d${YELLOW}' 保存配置！${NC}"
echo -e "${GREEN}==============================================${NC}"
