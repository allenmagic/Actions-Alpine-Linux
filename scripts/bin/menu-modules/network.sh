#!/bin/bash

# ==================== 联网设置模块 ====================

submenu_network() {
    while true; do
        # 获取当前 WAN 配置状态
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
