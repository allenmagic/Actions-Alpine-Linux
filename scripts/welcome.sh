#!/bin/bash

# 定义颜色代码
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
CYAN=$(printf '\033[0;36m')
RED=$(printf '\033[0;31m')
NC=$(printf '\033[0m')

# --- 1. 获取系统基本信息 ---
UPTIME=$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}' | sed 's/^ //')
LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
MEM_INFO=$(free -m | awk '/Mem:/ { printf "%sMB / %sMB (%.1f%%)", $3, $2, $3/$2*100 }')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
TEMP=$(cut -c1-2 /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "??")

# --- 2. 统计业务数据 ---
AD_COUNT=$(grep -c "address=/" /etc/dnsmasq.d/90-adblock.conf 2>/dev/null || echo "0")
PROXY_COUNT=$(grep -c "nftset=" /etc/dnsmasq.d/60-proxy-list.conf 2>/dev/null || echo "0")

VARS_FILE="/etc/nftables.d/vars.nft"
if [ -f "$VARS_FILE" ]; then
    grep -q "ppp0" "$VARS_FILE" && NET_MODE="PPPoE 拨号" || NET_MODE="光猫 DHCP"
else
    NET_MODE="${RED}未初始化${NC}"
fi

# --- 3. 打印欢迎界面 ---
echo "${CYAN}======================================================${NC}"
echo "   欢迎使用 ${GREEN}Alpine Linux${NC} (R3S 极简软路由版)"
echo "   系统时间: $(date "+%Y-%m-%d %H:%M:%S") | 温度: ${TEMP}°C"
echo "   运行时间: $UPTIME | 负载: $LOAD"
echo "   内存占用: $MEM_INFO"
echo "   根分区占用: $DISK_USAGE"
echo "${CYAN}------------------------------------------------------${NC}"

# --- 4. 业务状态看板 (使用 %b 处理颜色变量) ---
printf "   %b%-25s%b %b%-25s%b\n" "${YELLOW}[网络模式]: " "$NET_MODE" "${NC}" "${YELLOW}[在线设备]: " "$(grep -c "eth1" /proc/net/arp 2>/dev/null)" "${NC}"
printf "   %b%-25s%b %b%-25s%b\n" "${YELLOW}[广告拦截]: " "$AD_COUNT 条" "${NC}" "${YELLOW}[代理域名]: " "$PROXY_COUNT 个" "${NC}"
echo "${CYAN}------------------------------------------------------${NC}"

# --- 5. 核心工具说明 ---
echo "${GREEN}[核心管理指令]:${NC}"
echo "  • ${CYAN}network-setup${NC}  - 切换上网模式 (拨号/DHCP)"
echo "  • ${CYAN}update-adblock${NC} - 更新广告黑名单 (每周一自动运行)"
echo "  • ${CYAN}proxy add/list${NC} - 管理强制走代理的域名"
echo "  • ${CYAN}set-dns${NC}       - 快速修改上游解析服务器"
echo "  • ${CYAN}client-mgr${NC}    - 扫描内网设备并绑定固定 IP"
echo ""
echo "  ${RED}重要：${NC}修改配置后请运行 ${YELLOW}lbu commit -d${NC} 永久保存到 SD 卡"
echo "${CYAN}======================================================${NC}"

# --- 6. 初次登录特别引导 ---
if [ ! -f "$VARS_FILE" ]; then
    echo "${RED}>>> 检测到系统尚未完成网络初始化！${NC}"
    echo "${RED}>>> 请立即输入 ${GREEN}network-setup${RED} 开始配置。${NC}"
    echo "${CYAN}======================================================${NC}"
fi