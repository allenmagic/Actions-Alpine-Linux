#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # 重置颜色

# --- 1. 获取系统基本信息 ---
UPTIME=$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
MEM_FREE=$(free -m | awk '/Mem:/ { print $4 }')
MEM_TOTAL=$(free -m | awk '/Mem:/ { print $2 }')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')

# --- 2. 检查网络模式 ---
# 通过判断 vars.nft 内容或 ppp0 接口来识别模式
if [ -f /etc/nftables.d/vars.nft ]; then
    if grep -q "ppp0" /etc/nftables.d/vars.nft; then
        NET_MODE="PPPoE 拨号模式"
    else
        NET_MODE="光猫 DHCP 模式"
    fi
else
    NET_MODE="${RED}尚未初始化${NC}"
fi

# --- 3. 打印欢迎界面 ---
echo -e "${CYAN}======================================================${NC}"
echo -e "   欢迎使用 ${GREEN}Alpine Linux${NC} (R3S / PVE 软路由定制版)"
echo -e "   系统时间: $(date "+%Y-%m-%d %H:%M:%S")"
echo -e "   运行时间: $UPTIME"
echo -e "   系统负载: $LOAD"
echo -e "   内存剩余: ${MEM_FREE}MB / ${MEM_TOTAL}MB"
echo -e "   根分区占用: $DISK_USAGE"
echo -e "${CYAN}======================================================${NC}"

# --- 4. 核心功能说明 ---
echo -e "${YELLOW}[当前网络状态]${NC}: $NET_MODE"
echo -e ""
echo -e "${GREEN}[核心指令说明]:${NC}"
echo -e "  1. ${YELLOW}network-setup.sh${NC}    - 快速切换上网模式 (拨号/DHCP)"
echo -e "  2. ${YELLOW}lbu commit -d${NC}       - ${RED}重要！${NC}保存当前配置到 SD 卡/磁盘"
echo -e "  3. ${YELLOW}rc-service x restart${NC} - 重启服务 (x = nftables, dnsmasq, ppp.wan)"
echo -e ""
echo -e "${GREEN}[GitOps 管理]:${NC}"
echo -e "  - 配置文件目录: /etc/nftables.d/, /etc/dnsmasq.d/"
echo -e "  - 修改配置后请运行 ${YELLOW}lbu commit${NC} 以防重启丢失"
echo -e "${CYAN}======================================================${NC}"

# --- 5. 初次登录特别引导 ---
if [ ! -f /etc/nftables.d/vars.nft ]; then
    echo -e "${RED}>>> 检测到系统尚未完成网络初始化！${NC}"
    echo -e "${RED}>>> 请立即输入 ${GREEN}network-setup.sh${RED} 来配置您的网络。${NC}"
    echo -e "${CYAN}======================================================${NC}"
fi
