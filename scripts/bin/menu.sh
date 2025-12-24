#!/bin/bash

set -euo pipefail

# 全局常量
readonly WAN_IF="eth0"
readonly LAN_IF="eth1"

# --- 数据采集函数 ---
get_status_bar() {
    local TEMP
    TEMP="$(cut -c1-2 /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "??")"

    local MEM
    MEM="$(free -m | awk '/Mem:/ {printf "%d/%dMB", $3, $2}')"

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

    local LAN_COUNT
    LAN_COUNT="$(awk '$3 == "0x2" {count++} END {print count+0}' /proc/net/arp 2>/dev/null)"

    local INFO="温度: ${TEMP}°C | 内存: ${MEM} | WAN: ${WAN_DISPLAY} | 在线: ${LAN_COUNT}"
    local DEV="开发者: allenmagic"

    printf "      %s      |      %s" "$INFO" "$DEV"
}

# --- 子功能：代理分流管理 ---
# --- 子功能：代理分流管理 ---
submenu_proxy() {
    while true; do
        # 统计代理规则数量（容错处理）
        local RULE_COUNT
        if command -v nft >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
            RULE_COUNT="$(nft -j list set inet singbox proxy_set 2>/dev/null | \
                jq -r '.nftables[]?.set?.elem? | length' 2>/dev/null || echo 0)"
        else
            RULE_COUNT="N/A"
        fi

        local SUB_CHOICE
        SUB_CHOICE=$(whiptail --title "代理分流管理" --backtitle "$(get_status_bar)" \
            --menu "当前代理 IP 数: $RULE_COUNT" 15 60 4 \
            "1" "更新 GFWList 规则" \
            "2" "查看当前代理规则" \
            "3" "编辑手动代理名单" \
            "B" "返回主菜单" 3>&1 1>&2 2>&3) || break

        case "$SUB_CHOICE" in
            1)
                # 更新 GFWList 规则
                if [ ! -x /usr/local/bin/update-gfwlist.sh ]; then
                    whiptail --msgbox "错误: /usr/local/bin/update-gfwlist.sh 不存在或无执行权限\n\n请先安装更新脚本。" 10 60
                    continue
                fi

                if whiptail --yesno "确定更新 GFWList 规则？\n这可能需要几分钟时间。" 10 50; then
                    if /usr/local/bin/update-gfwlist.sh 2>&1 | tee /tmp/gfwlist-update.log; then
                        # 重新统计规则数
                        local NEW_COUNT
                        if command -v nft >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
                            NEW_COUNT="$(nft -j list set inet singbox proxy_set 2>/dev/null | \
                                jq -r '.nftables[]?.set?.elem? | length' 2>/dev/null || echo 0)"
                        else
                            NEW_COUNT="未知"
                        fi
                        whiptail --title "更新成功" --msgbox "GFWList 规则已更新！\n当前规则数: $NEW_COUNT" 10 45
                    else
                        whiptail --title "更新失败" --textbox /tmp/gfwlist-update.log 20 70
                    fi
                fi
                ;;

            2)
                # 查看当前代理规则
                if ! command -v nft >/dev/null 2>&1; then
                    whiptail --msgbox "错误: nftables 未安装\n\n请先安装: apk add nftables" 10 50
                    continue
                fi

                # 检查规则集是否存在
                if ! nft list set inet singbox proxy_set >/dev/null 2>&1; then
                    whiptail --msgbox "错误: 规则集 'inet singbox proxy_set' 不存在\n\n可能原因:\n- nftables 服务未启动\n- 规则集尚未创建\n- 表名或集合名不正确" 12 60
                    continue
                fi

                # 导出规则到临时文件
                {
                    echo "=== 代理分流规则集 ==="
                    echo "表: inet singbox"
                    echo "集合: proxy_set"
                    echo ""
                    nft list set inet singbox proxy_set 2>/dev/null
                } > /tmp/proxy-rules.txt

                # 检查是否有内容
                if [ -s /tmp/proxy-rules.txt ]; then
                    whiptail --title "代理规则" --textbox /tmp/proxy-rules.txt 20 80
                else
                    whiptail --msgbox "规则集为空或无法读取。" 8 40
                fi
                ;;

            3)
                # 编辑手动代理名单
                local RAW_FILE="/etc/proxy_list.raw"
                local GEN_SCRIPT="/usr/local/bin/gen-proxy-conf.sh"

                # 检查生成脚本是否存在
                if [ ! -x "$GEN_SCRIPT" ]; then
                    whiptail --msgbox "错误: $GEN_SCRIPT 不存在或无执行权限\n\n请先安装配置生成脚本。" 10 60
                    continue
                fi

                # 检查编辑器是否存在
                if ! command -v nano >/dev/null 2>&1; then
                    whiptail --msgbox "错误: nano 编辑器未安装\n\n请先安装: apk add nano" 10 50
                    continue
                fi

                # 确保文件存在
                if [ ! -f "$RAW_FILE" ]; then
                    cat > "$RAW_FILE" <<'EOF'
# 手动代理名单
# 每行一个域名或 IP 地址
# 示例:
# google.com
# youtube.com
# 1.2.3.4

EOF
                fi

                # 编辑文件
                nano -w "$RAW_FILE"

                # 用户确认
                if whiptail --yesno "是否应用更改？" 8 40; then
                    if "$GEN_SCRIPT" 2>&1 | tee /tmp/proxy-apply.log; then
                        local COUNT
                        COUNT="$(grep -cvE '^\s*#|^\s*$' "$RAW_FILE" 2>/dev/null || echo 0)"
                        whiptail --title "成功" --msgbox "配置已更新！\n共加载 $COUNT 条有效记录。" 10 45
                    else
                        whiptail --title "错误" --textbox /tmp/proxy-apply.log 15 60
                    fi
                else
                    whiptail --msgbox "已取消应用更改。" 8 40
                fi
                ;;

            B|b)
                break
                ;;
        esac
    done
}

# --- 子功能：联网设置 ---
submenu_network() {
    while true; do
        local wan_mode="未知"
        local wan_info=""

        if grep -q "iface $WAN_IF inet dhcp" /etc/network/interfaces 2>/dev/null; then
            wan_mode="DHCP"
            wan_info="$(ip -4 addr show "$WAN_IF" 2>/dev/null | awk '/inet / {print $2}' || echo "未获取到 IP")"
        elif grep -q "iface $WAN_IF inet manual" /etc/network/interfaces 2>/dev/null; then
            wan_mode="PPPoE"
            wan_info="$(ip -4 addr show ppp0 2>/dev/null | awk '/inet / {print $2}' || echo "未拨号")"
        elif grep -q "iface $WAN_IF inet static" /etc/network/interfaces 2>/dev/null; then
            wan_mode="静态IP"
            wan_info="$(ip -4 addr show "$WAN_IF" 2>/dev/null | awk '/inet / {print $2}' || echo "未配置")"
        fi

        local NET_CHOICE
        NET_CHOICE=$(whiptail --title "联网设置" --backtitle "$(get_status_bar)" \
            --menu "当前模式: $wan_mode ($wan_info)" 18 65 6 \
            "1" "配置 DHCP 上网 (自动获取 IP)" \
            "2" "配置 PPPoE 拨号上网" \
            "3" "配置静态 IP 上网" \
            "4" "查看当前网络配置" \
            "5" "测试网络连通性" \
            "B" "返回主菜单" 3>&1 1>&2 2>&3) || break

        case "$NET_CHOICE" in
            1)
                if whiptail --yesno "确定切换到 DHCP 模式？\n当前配置将被覆盖。" 10 50; then
                    if /usr/local/bin/network-setup.sh dhcp 2>&1 | tee /tmp/network-setup.log; then
                        whiptail --title "成功" --msgbox "DHCP 模式配置完成！" 8 40
                    else
                        whiptail --title "失败" --textbox /tmp/network-setup.log 20 70
                    fi
                fi
                ;;
            2)
                local ppp_user ppp_pass
                ppp_user=$(whiptail --inputbox "请输入拨号账号:" 10 50 3>&1 1>&2 2>&3) || continue
                [ -z "$ppp_user" ] && continue

                ppp_pass=$(whiptail --passwordbox "请输入拨号密码:" 10 50 3>&1 1>&2 2>&3) || continue
                [ -z "$ppp_pass" ] && continue

                if whiptail --yesno "确定使用以下信息拨号？\n账号: $ppp_user" 10 50; then
                    if /usr/local/bin/network-setup.sh pppoe "$ppp_user" "$ppp_pass" 2>&1 | tee /tmp/network-setup.log; then
                        whiptail --title "成功" --msgbox "PPPoE 拨号配置完成！" 8 40
                    else
                        whiptail --title "失败" --textbox /tmp/network-setup.log 20 70
                    fi
                fi
                ;;
            3)
                local static_ip static_mask static_gw static_dns
                static_ip=$(whiptail --inputbox "WAN 口 IP 地址:" 10 50 "192.168.1.100" 3>&1 1>&2 2>&3) || continue
                [ -z "$static_ip" ] && continue

                static_mask=$(whiptail --inputbox "子网掩码:" 10 50 "255.255.255.0" 3>&1 1>&2 2>&3) || continue
                [ -z "$static_mask" ] && continue

                static_gw=$(whiptail --inputbox "网关地址:" 10 50 "192.168.1.1" 3>&1 1>&2 2>&3) || continue
                [ -z "$static_gw" ] && continue

                static_dns=$(whiptail --inputbox "DNS 服务器:" 10 50 "223.5.5.5" 3>&1 1>&2 2>&3) || continue
                [ -z "$static_dns" ] && continue

                if whiptail --yesno "确定使用以下配置？\nIP: $static_ip\n掩码: $static_mask\n网关: $static_gw\nDNS: $static_dns" 12 50; then
                    if /usr/local/bin/network-setup.sh static "$static_ip" "$static_mask" "$static_gw" "$static_dns" 2>&1 | tee /tmp/network-setup.log; then
                        whiptail --title "成功" --msgbox "静态 IP 配置完成！" 8 40
                    else
                        whiptail --title "失败" --textbox /tmp/network-setup.log 20 70
                    fi
                fi
                ;;
            4)
                {
                    cat /etc/network/interfaces
                    echo -e "\n=== 当前 IP 地址 ==="
                    ip addr show
                    echo -e "\n=== 路由表 ==="
                    ip route show
                } > /tmp/network-config.txt
                whiptail --title "网络配置" --textbox /tmp/network-config.txt 20 70
                ;;
            5)
                if ping -c 3 -W 5 223.5.5.5 > /tmp/ping-test.log 2>&1; then
                    whiptail --title "连通性测试" --msgbox "网络连接正常！" 8 40
                else
                    whiptail --title "连通性测试" --textbox /tmp/ping-test.log 15 60
                fi
                ;;
            B|b)
                break
                ;;
        esac
    done
}

# --- 子功能：广告拦截管理 ---
# --- 子功能：广告拦截管理 ---
submenu_adblock() {
    while true; do
        # 统计当前拦截规则数量（容错处理）
        local AD_COUNT
        if [ -d /etc/dnsmasq.d ]; then
            AD_COUNT="$(find /etc/dnsmasq.d -name '*adblock*.conf' -type f -exec wc -l {} + 2>/dev/null | awk 'END {print $1+0}')"
        else
            AD_COUNT=0
        fi

        local AD_CHOICE
        AD_CHOICE=$(whiptail --title "广告拦截管理" --backtitle "$(get_status_bar)" \
            --menu "当前拦截规则: $AD_COUNT 条" 12 60 3 \
            "1" "更新广告拦截规则" \
            "2" "清空所有拦截规则" \
            "B" "返回主菜单" 3>&1 1>&2 2>&3) || break

        case "$AD_CHOICE" in
            1)
                # 更新广告拦截规则
                if [ -x /usr/local/bin/update-adblock.sh ]; then
                    if whiptail --yesno "确定更新广告拦截规则？\n这可能需要几分钟时间。" 10 50; then
                        # 执行更新
                        if /usr/local/bin/update-adblock.sh 2>&1 | tee /tmp/adblock-update.log; then
                            # 重新统计规则数
                            local NEW_COUNT
                            if [ -d /etc/dnsmasq.d ]; then
                                NEW_COUNT="$(find /etc/dnsmasq.d -name '*adblock*.conf' -type f -exec wc -l {} + 2>/dev/null | awk 'END {print $1+0}')"
                            else
                                NEW_COUNT=0
                            fi
                            whiptail --title "更新成功" --msgbox "广告拦截规则已更新！\n当前规则数: $NEW_COUNT 条" 10 45
                        else
                            whiptail --title "更新失败" --textbox /tmp/adblock-update.log 20 70
                        fi
                    fi
                else
                    whiptail --msgbox "错误: /usr/local/bin/update-adblock.sh 不存在或无执行权限\n\n请先安装更新脚本。" 10 60
                fi
                ;;

            2)
                # 清空所有拦截规则
                if [ "$AD_COUNT" -eq 0 ]; then
                    whiptail --msgbox "当前没有任何拦截规则。" 8 40
                    continue
                fi

                if whiptail --title "危险操作" --yesno "确定要清空所有广告拦截规则吗？\n\n当前规则数: $AD_COUNT 条\n\n此操作不可恢复！" 12 60; then
                    # 二次确认
                    if whiptail --title "最后确认" --yesno "真的要删除所有规则吗？" 8 50; then
                        # 删除规则文件
                        local deleted=0
                        if [ -d /etc/dnsmasq.d ]; then
                            find /etc/dnsmasq.d -name '*adblock*.conf' -type f -delete 2>/dev/null && deleted=1
                            find /etc/dnsmasq.d -name '*ad*.conf' -type f -delete 2>/dev/null
                        fi

                        if [ "$deleted" -eq 1 ]; then
                            # 重启 dnsmasq
                            if command -v rc-service >/dev/null 2>&1 && rc-service dnsmasq restart 2>/dev/null; then
                                whiptail --msgbox "所有广告拦截规则已清空！" 8 40
                            elif command -v systemctl >/dev/null 2>&1 && systemctl restart dnsmasq 2>/dev/null; then
                                whiptail --msgbox "所有广告拦截规则已清空！" 8 40
                            else
                                whiptail --msgbox "规则已删除，但 dnsmasq 重启失败\n请手动执行重启命令。" 10 50
                            fi
                        else
                            whiptail --msgbox "未找到可删除的规则文件。" 8 40
                        fi
                    fi
                fi
                ;;

            B|b)
                break
                ;;
        esac
    done
}


# --- 主菜单（去掉 --timeout 和自动刷新） ---
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
                # 手动刷新：直接 continue 回到循环开头
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

# --- 主程序入口 ---
main_menu
