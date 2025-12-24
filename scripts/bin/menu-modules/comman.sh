#!/bin/bash

# ==================== 公共函数模块 ====================

# --- 数据采集函数 ---
get_status_bar() {
    # 1. 获取温度
    local TEMP
    TEMP="$(cut -c1-2 /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "??")"

    # 2. 获取内存
    local MEM
    MEM="$(free -m | awk '/Mem:/ {printf "%d/%dMB", $3, $2}')"

    # 3. 获取 WAN 信息
    local wan_if_actual
    local WAN_MODE
    local WAN_IP
    local WAN_DISPLAY

    if ip addr show ppp0 >/dev/null 2>&1; then
        wan_if_actual="ppp0"
        WAN_MODE="PPPoE"
    elif ip addr show "$WAN_IF" >/dev/null 2>&1; then
        wan_if_actual="$WAN_IF"
        WAN_MODE="WAN"
    else
        wan_if_actual=""
        WAN_MODE="未连接"
    fi

    if [ -n "$wan_if_actual" ]; then
        WAN_IP="$(ip -4 addr show "$wan_if_actual" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)"
    fi

    if [ -z "${WAN_IP:-}" ]; then
        WAN_DISPLAY="未连接"
    else
        if ping -c 1 -W 1 -q 223.5.5.5 >/dev/null 2>&1; then
            WAN_DISPLAY="${WAN_MODE} - ${WAN_IP}"
        else
            WAN_DISPLAY="${WAN_MODE} - 无互联网接入"
        fi
    fi

    # 4. 获取 LAN 客户端数量
    local LAN_COUNT
    LAN_COUNT="$(awk '$3 == "0x2" {count++} END {print count+0}' /proc/net/arp 2>/dev/null)"

    # 5. 构造信息行
    local INFO="温度: ${TEMP}°C | 内存: ${MEM} | WAN: ${WAN_DISPLAY} | 在线: ${LAN_COUNT}"
    local DEV="开发者: allenmagic"

    # 6. 输出状态栏
    printf "      %s      |      %s" "$INFO" "$DEV"
}
