#!/bin/sh
# /usr/local/bin/network-monitor.sh
# 网络服务监控脚本 - 完整版（包含子网掩码）

set -e

# ==================== 配置参数 ====================
readonly LAN_IF="eth1"
readonly WAN_IF="eth0"
readonly LAN_IP="192.168.8.1"
readonly LAN_NETMASK="255.255.255.0"
readonly LAN_BROADCAST="192.168.8.255"
readonly DHCP_START="192.168.8.100"
readonly DHCP_END="192.168.8.200"
readonly DHCP_LEASE="12h"
readonly DNS_REMOTE="223.5.5.5"
readonly DNS_BACKUP="114.114.114.114"
readonly DOMAIN_NAME="lan"

readonly LOG_FILE="/var/log/network-monitor.log"
readonly FAILSAFE_FLAG="/var/run/network-failsafe"
readonly DAEMON_PID="/var/run/network-monitor.pid"

readonly RESTART_WAIT=5
readonly MONITOR_INTERVAL=300
readonly BOOT_WAIT=60

# ==================== 工具函数 ====================
log() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$LOG_FILE"
    logger -t network-monitor "$level: $message" 2>/dev/null || true
}

# ==================== 检测函数 ====================
check_dnsmasq_process() {
    pgrep -x dnsmasq >/dev/null 2>&1
}

check_nftables_rules() {
    [ "$(nft list ruleset 2>/dev/null | wc -l)" -gt 5 ] && \
    nft list table inet nat >/dev/null 2>&1 && \
    nft list table inet nat 2>/dev/null | grep -q "masquerade" && \
    [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = "1" ]
}

is_service_managed() {
    local service="$1"
    rc-service --exists "$service" 2>/dev/null
}

get_service_status() {
    local service="$1"
    rc-service "$service" status 2>/dev/null | grep -q "started"
}

# ==================== 兜底策略 ====================
failsafe_dns() {
    log "CRITICAL" "启动 DNS 兜底模式"

    if is_service_managed dnsmasq; then
        log "INFO" "禁用 OpenRC 的 dnsmasq 服务"
        rc-update del dnsmasq default 2>/dev/null || true
        rc-service dnsmasq stop 2>/dev/null || true
    fi

    pkill -9 dnsmasq 2>/dev/null || true
    sleep 2

    /usr/sbin/dnsmasq \
        --interface="$LAN_IF" \
        --bind-interfaces \
        --listen-address="$LAN_IP" \
        --dhcp-range="$DHCP_START,$DHCP_END,$DHCP_LEASE" \
        --dhcp-option=option:netmask,"$LAN_NETMASK" \
        --dhcp-option=option:router,"$LAN_IP" \
        --dhcp-option=option:dns-server,"$DNS_REMOTE" \
        --dhcp-option=option:domain-name,"$DOMAIN_NAME" \
        --dhcp-option=option:broadcast,"$LAN_BROADCAST" \
        --server="$DNS_REMOTE" \
        --server="$DNS_BACKUP" \
        --no-resolv \
        --no-poll \
        --no-hosts \
        --conf-file=/dev/null \
        --pid-file="/var/run/dnsmasq-failsafe.pid" \
        --log-facility=/var/log/dnsmasq-failsafe.log \
        --log-dhcp \
        </dev/null >/dev/null 2>&1 &

    sleep 3

    if check_dnsmasq_process; then
        touch "$FAILSAFE_FLAG.dns"
        log "CRITICAL" "DNS 兜底模式已激活（PID: $(cat /var/run/dnsmasq-failsafe.pid 2>/dev/null || echo 'unknown')）"
        log "CRITICAL" "配置信息："
        log "CRITICAL" "  - 接口: $LAN_IF"
        log "CRITICAL" "  - IP: $LAN_IP"
        log "CRITICAL" "  - 子网掩码: $LAN_NETMASK"
        log "CRITICAL" "  - 广播地址: $LAN_BROADCAST"
        log "CRITICAL" "  - DHCP 范围: $DHCP_START - $DHCP_END"
        log "CRITICAL" "  - 租约时间: $DHCP_LEASE"
        log "CRITICAL" "  - 网关: $LAN_IP"
        log "CRITICAL" "  - DNS: $DNS_REMOTE, $DNS_BACKUP"
        log "CRITICAL" "  - 域名: $DOMAIN_NAME"
        log "CRITICAL" "恢复步骤："
        log "CRITICAL" "  1. 修复 /etc/dnsmasq.conf"
        log "CRITICAL" "  2. pkill -9 dnsmasq"
        log "CRITICAL" "  3. rm $FAILSAFE_FLAG.dns"
        log "CRITICAL" "  4. rc-update add dnsmasq default"
        log "CRITICAL" "  5. rc-service dnsmasq start"
    else
        log "CRITICAL" "DNS 兜底模式启动失败！"
    fi
}

failsafe_nftables() {
    log "CRITICAL" "启动防火墙兜底模式"

    if is_service_managed nftables; then
        log "INFO" "禁用 OpenRC 的 nftables 服务"
        rc-update del nftables default 2>/dev/null || true
        rc-service nftables stop 2>/dev/null || true
    fi

    nft flush ruleset 2>/dev/null || true
    sleep 1

    nft add table inet filter
    nft add chain inet filter input '{ type filter hook input priority 0; policy accept; }'
    nft add chain inet filter forward '{ type filter hook forward priority 0; policy accept; }'
    nft add chain inet filter output '{ type filter hook output priority 0; policy accept; }'

    nft add table inet nat
    nft add chain inet nat postrouting '{ type nat hook postrouting priority 100; policy accept; }'
    nft add rule inet nat postrouting oifname "$WAN_IF" masquerade

    echo 1 > /proc/sys/net/ipv4/ip_forward

    if check_nftables_rules; then
        touch "$FAILSAFE_FLAG.nft"
        log "CRITICAL" "防火墙兜底模式已激活"
        log "CRITICAL" "恢复步骤："
        log "CRITICAL" "  1. 修复 /etc/nftables.conf"
        log "CRITICAL" "  2. rm $FAILSAFE_FLAG.nft"
        log "CRITICAL" "  3. rc-update add nftables default"
        log "CRITICAL" "  4. rc-service nftables start"
    else
        log "CRITICAL" "防火墙兜底模式启动失败！"
    fi
}

# ==================== 监控逻辑 ====================
monitor_dnsmasq() {
    if [ -f "$FAILSAFE_FLAG.dns" ]; then
        log "DEBUG" "DNS 处于兜底模式，跳过监控"
        return
    fi

    if check_dnsmasq_process; then
        log "DEBUG" "dnsmasq 进程正常"
        return
    fi

    log "WARN" "检测到 dnsmasq 进程未运行"

    if is_service_managed dnsmasq; then
        if get_service_status dnsmasq; then
            log "WARN" "OpenRC 显示 dnsmasq 已启动，但进程不存在"
        else
            log "WARN" "OpenRC 显示 dnsmasq 未启动"
        fi
    fi

    log "INFO" "尝试通过 OpenRC 重启 dnsmasq..."

    local restart_log="/tmp/dnsmasq-restart-$(date +%s).log"
    if rc-service dnsmasq restart >"$restart_log" 2>&1; then
        log "INFO" "dnsmasq 重启命令执行成功"
    else
        log "ERROR" "dnsmasq 重启失败: $(cat "$restart_log")"
        failsafe_dns
        return
    fi

    sleep "$RESTART_WAIT"

    if check_dnsmasq_process; then
        log "INFO" "dnsmasq 重启成功"
        rm -f "$restart_log"
    else
        log "ERROR" "dnsmasq 重启后仍未运行"
        failsafe_dns
    fi
}

monitor_nftables() {
    if [ -f "$FAILSAFE_FLAG.nft" ]; then
        log "DEBUG" "防火墙处于兜底模式，跳过监控"
        return
    fi

    if check_nftables_rules; then
        log "DEBUG" "nftables 规则正常"
        return
    fi

    log "WARN" "检测到 nftables 规则异常"

    if is_service_managed nftables; then
        if get_service_status nftables; then
            log "WARN" "OpenRC 显示 nftables 已启动，但规则异常"
        else
            log "WARN" "OpenRC 显示 nftables 未启动"
        fi
    fi

    log "INFO" "尝试通过 OpenRC 重启 nftables..."

    local restart_log="/tmp/nftables-restart-$(date +%s).log"
    if rc-service nftables restart >"$restart_log" 2>&1; then
        log "INFO" "nftables 重启命令执行成功"
    else
        log "ERROR" "nftables 重启失败: $(cat "$restart_log")"
        failsafe_nftables
        return
    fi

    sleep "$RESTART_WAIT"

    if check_nftables_rules; then
        log "INFO" "nftables 重启成功"
        rm -f "$restart_log"
    else
        log "ERROR" "nftables 重启后仍异常"
        failsafe_nftables
    fi
}

monitor_ssh() {
    if ! pgrep -x sshd >/dev/null 2>&1; then
        log "WARN" "SSH 进程未运行，尝试启动"
        rc-service sshd start >/dev/null 2>&1 || true
    fi
}

# ==================== 单次检查 ====================
check_once() {
    log "INFO" "开始监控检查"
    monitor_dnsmasq
    monitor_nftables
    monitor_ssh
    log "INFO" "监控检查完成"
}

# ==================== 开机自检 ====================
boot_check() {
    log "INFO" "========== 开机自检开始 =========="

    log "INFO" "等待 ${BOOT_WAIT} 秒，让 OpenRC 完成服务启动..."
    sleep "$BOOT_WAIT"

    log "INFO" "检查 OpenRC 启动状态..."
    if rc-status -r 2>/dev/null | grep -q "default"; then
        log "INFO" "OpenRC 已进入 default runlevel"
    else
        log "WARN" "OpenRC 可能尚未完成启动"
    fi

    check_once

    log "INFO" "========== 开机自检完成 =========="
}

# ==================== 守护进程 ====================
daemon_start() {
    if [ -f "$DAEMON_PID" ]; then
        local old_pid=$(cat "$DAEMON_PID")
        if kill -0 "$old_pid" 2>/dev/null; then
            log "WARN" "守护进程已在运行 (PID: $old_pid)"
            return
        fi
    fi

    log "INFO" "启动监控守护进程（间隔: ${MONITOR_INTERVAL}秒）"

    (
        echo $$ > "$DAEMON_PID"

        while true; do
            sleep "$MONITOR_INTERVAL"
            check_once
        done
    ) &

    log "INFO" "守护进程已启动 (PID: $(cat "$DAEMON_PID"))"
}

daemon_stop() {
    if [ -f "$DAEMON_PID" ]; then
        local pid=$(cat "$DAEMON_PID")
        if kill -0 "$pid" 2>/dev/null; then
            log "INFO" "停止守护进程 (PID: $pid)"
            kill "$pid"
            rm -f "$DAEMON_PID"
        else
            log "WARN" "守护进程未运行"
            rm -f "$DAEMON_PID"
        fi
    else
        log "WARN" "守护进程未运行"
    fi
}

# ==================== 主程序 ====================
case "${1:-check}" in
    boot)
        boot_check
        ;;
    daemon-start)
        daemon_start
        ;;
    daemon-stop)
        daemon_stop
        ;;
    check)
        check_once
        ;;
    *)
        echo "用法: $0 {boot|daemon-start|daemon-stop|check}"
        exit 1
        ;;
esac
