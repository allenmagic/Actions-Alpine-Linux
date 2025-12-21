#!/bin/bash

# Copyright (c) 2025 allenmagic
# Author: allenmagic
# License: MIT

# 颜色定义
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 配置文件路径
DNSMASQ_STATIC_CONF="/etc/dnsmasq.d/static_leases.conf"
LEASE_FILE="/var/lib/misc/dnsmasq.leases"

# 确保静态配置文件目录存在
mkdir -p /etc/dnsmasq.d
touch $DNSMASQ_STATIC_CONF

# --- 1. 获取设备列表函数 ---
list_clients() {
    echo -e "${CYAN}ID\tIPv4\t\tIPv6\t\tMAC\t\tType\tName${NC}"
    echo "--------------------------------------------------------------------------------"
    
    # 临时存储数组，方便后续根据 ID 操作
    declare -gA CLIENT_IPS
    declare -gA CLIENT_MACS
    declare -gA CLIENT_NAMES
    
    local i=1
    # 结合 dnsmasq.leases 和 IPv6 邻居表
    # 读取当前的 DHCP 租约
    while read -r expire mac ip name duid; do
        # 检查是否已经在静态配置文件中
        if grep -q "$mac" "$DNSMASQ_STATIC_CONF"; then
            type="${GREEN}Static${NC}"
        else
            type="${YELLOW}DHCP${NC}"
        fi
        
        # 尝试查找对应的 IPv6 地址 (通过 ip -6 neigh)
        ipv6=$(ip -6 neigh show | grep -i "$mac" | awk '{print $1}' | head -n 1)
        [ -z "$ipv6" ] && ipv6="--"

        echo -e "$i\t$ip\t$ipv6\t$mac\t$type\t$name"
        
        # 存入数组备用
        CLIENT_IPS[$i]=$ip
        CLIENT_MACS[$i]=$mac
        CLIENT_NAMES[$i]=$name
        
        i=$((i+1))
    done < "$LEASE_FILE"
}

# --- 2. 绑定静态 IP 函数 (支持自定义 IP) ---
bind_static() {
    read -p "请输入要操作的设备序号 (ID): " id
    
    local target_ip=${CLIENT_IPS[$id]}
    local target_mac=${CLIENT_MACS[$id]}
    local target_name=${CLIENT_NAMES[$id]}

    if [ -z "$target_ip" ]; then
        echo -e "${RED}[错误] 无效的序号${NC}"
        sleep 2
        return
    fi

    echo -e "\n${YELLOW}设备信息: $target_name ($target_mac)${NC}"
    echo -e "当前分配的 IP: ${CYAN}$target_ip${NC}"
    
    # 允许用户输入自定义 IP
    read -p "请输入要绑定的固定 IP [直接回车使用当前 IP]: " manual_ip
    
    # 如果用户输入了内容，则使用输入的 IP，否则保持原样
    local final_ip=${manual_ip:-$target_ip}

    # 简单的格式校验 (仅检查是否非空且符合基本 IP 结构)
    if [[ ! $final_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}[错误] IP 地址格式不正确！${NC}"
        sleep 2
        return
    fi

    echo -e "${YELLOW}正在保存配置: $target_mac -> $final_ip${NC}"
    
    # 检查并清理旧的绑定记录（防止同一个 MAC 对应多个 IP）
    if [ -f "$DNSMASQ_STATIC_CONF" ]; then
        sed -i "/$target_mac/d" "$DNSMASQ_STATIC_CONF"
    fi

    # 写入 Dnsmasq 静态租约格式
    # 格式: dhcp-host=MAC,IP,HOSTNAME
    echo "dhcp-host=$target_mac,$final_ip,$target_name" >> "$DNSMASQ_STATIC_CONF"
    
    echo -e "${GREEN}[成功] 配置已写入 $DNSMASQ_STATIC_CONF${NC}"
    
    # 重启服务使配置即时生效
    rc-service dnsmasq restart >/dev/null
    echo -e "${GREEN}[完成] Dnsmasq 已重启。请记得运行 'lbu commit -d' 保存到存储介质！${NC}"
    sleep 3
}

# --- 主逻辑 ---
while :
do
    clear
    echo -e "${GREEN}=== Alpine Linux 软路由设备管理工具 ===${NC}"
    list_clients
    echo "--------------------------------------------------------------------------------"
    echo "选项: [b] 绑定序号设备为固定IP | [r] 刷新列表 | [q] 退出"
    read -p "请选择操作: " opt

    case $opt in
        b) bind_static ;;
        r) continue ;;
        q) exit 0 ;;
        *) echo "无效选项" ; sleep 1 ;;
    esac
done
