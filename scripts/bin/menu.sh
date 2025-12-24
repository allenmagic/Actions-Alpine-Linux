#!/bin/bash

set -euo pipefail

# ==================== 全局常量定义 ====================
readonly WAN_IF="eth0"
readonly LAN_IF="eth1"
readonly MODULE_DIR="./menu-modules"

# ==================== 加载模块 ====================
# 检查模块目录是否存在
if [ ! -d "$MODULE_DIR" ]; then
    echo "错误: 模块目录 $MODULE_DIR 不存在"
    exit 1
fi

# 加载所有模块
for module in "$MODULE_DIR"/*.sh; do
    if [ -f "$module" ]; then
        # shellcheck source=/dev/null
        source "$module"
    fi
done

# ==================== 主菜单 ====================
main_menu() {
    local DEFAULT_ITEM="1"

    while true; do
        local STATUS_BAR
        STATUS_BAR="$(get_status_bar)"

        local CHOICE
        CHOICE=$(whiptail --title "R3S 管理面板 (Alpine Linux)" \
            --backtitle "$STATUS_BAR" \
            --default-item "$DEFAULT_ITEM" \
            --menu "\n\n请使用方向键导航:" 20 70 10 \
            "1" "联网设置 (DHCP/PPPoE/Static)" \
            "2" "广告拦截 (AdBlock) 管理" \
            "3" "代理分流 (Nftset) 管理" \
            "4" "局域网设置" \
            "5" "查看系统实时日志" \
            "R" "手动刷新状态栏" \
            "S" "保存更改到 SD 卡 (LBU COMMIT)" \
            "X" "退出到命令行 (Shell)" \
            "Q" "退出并关闭连接" 3>&1 1>&2 2>&3)

        local EXIT_STATUS=$?

        if [ $EXIT_STATUS -ne 0 ]; then
            clear
            exit 0
        fi

        DEFAULT_ITEM="$CHOICE"

        case "$CHOICE" in
            1) submenu_network ;;
            2) submenu_adblock ;;
            3) submenu_proxy ;;
            4)
                if command -v client-mgr >/dev/null 2>&1; then
                    client-mgr
                else
                    whiptail --msgbox "client-mgr 命令不存在" 8 40
                fi
                read -rp "按回车继续..."
                ;;
            5)
                logread -f || whiptail --msgbox "无法读取日志" 8 40
                ;;
            [rR])
                continue
                ;;
            [sS])
                if whiptail --title "持久化保存" --yesno "确定将配置写入 SD 卡？" 10 60; then
                    if lbu commit -df; then
                        whiptail --msgbox "保存成功！" 8 40
                    else
                        whiptail --msgbox "保存失败，请检查权限" 8 40
                    fi
                fi
                ;;
            [xX])
                clear
                exit 0
                ;;
            [qQ])
                clear
                exit 0
                ;;
        esac
    done
}

# ==================== 主程序入口 ====================
main_menu
