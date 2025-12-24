#!/bin/bash
# /usr/local/bin/menu-modules/adblock.sh
# 功能：广告拦截管理 UI

submenu_adblock() {
    while true; do
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
                # 检查更新脚本
                if [ ! -x /usr/local/bin/update-adblock.sh ]; then
                    whiptail --msgbox "错误: /usr/local/bin/update-adblock.sh 不存在或无执行权限\n\n请先安装更新脚本。" 10 60
                    continue
                fi

                # 确认更新
                if ! whiptail --yesno "确定更新广告拦截规则？\n\n数据源: anti-ad.net\n预计时间: 1-3 分钟" 12 50; then
                    continue
                fi

                # 执行更新（捕获输出）
                if /usr/local/bin/update-adblock.sh 2>&1 | tee /tmp/adblock-update.log; then
                    # 更新成功，重新统计
                    local NEW_COUNT
                    if [ -d /etc/dnsmasq.d ]; then
                        NEW_COUNT="$(find /etc/dnsmasq.d -name '*adblock*.conf' -type f -exec wc -l {} + 2>/dev/null | awk 'END {print $1+0}')"
                    else
                        NEW_COUNT=0
                    fi
                    whiptail --title "更新成功" --msgbox "广告拦截规则已更新！\n\n当前规则数: $NEW_COUNT 条\n\n详细日志: /tmp/adblock-update.log" 12 50
                else
                    # 更新失败，显示日志
                    whiptail --title "更新失败" --msgbox "更新过程中出现错误\n\n请查看详细日志" 10 50
                    whiptail --title "错误日志" --textbox /tmp/adblock-update.log 20 70
                fi
                ;;

            2)
                # 清空规则（保持原有逻辑）
                if [ "$AD_COUNT" -eq 0 ]; then
                    whiptail --msgbox "当前没有任何拦截规则。" 8 40
                    continue
                fi

                if whiptail --title "危险操作" --yesno "确定要清空所有广告拦截规则吗？\n\n当前规则数: $AD_COUNT 条\n\n此操作不可恢复！" 12 60; then
                    if whiptail --title "最后确认" --yesno "真的要删除所有规则吗？" 8 50; then
                        local deleted=0
                        if [ -d /etc/dnsmasq.d ]; then
                            find /etc/dnsmasq.d -name '*adblock*.conf' -type f -delete 2>/dev/null && deleted=1
                        fi

                        if [ "$deleted" -eq 1 ]; then
                            if pgrep dnsmasq > /dev/null; then
                                killall -SIGHUP dnsmasq 2>/dev/null || rc-service dnsmasq restart 2>/dev/null
                            fi
                            whiptail --msgbox "所有广告拦截规则已清空！" 8 40
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
