#!/bin/bash

# ==================== 代理分流模块 ====================

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

                if ! nft list set inet singbox proxy_set >/dev/null 2>&1; then
                    whiptail --msgbox "错误: 规则集 'inet singbox proxy_set' 不存在\n\n可能原因:\n- nftables 服务未启动\n- 规则集尚未创建\n- 表名或集合名不正确" 12 60
                    continue
                fi

                {
                    echo "=== 代理分流规则集 ==="
                    echo "表: inet singbox"
                    echo "集合: proxy_set"
                    echo ""
                    nft list set inet singbox proxy_set 2>/dev/null
                } > /tmp/proxy-rules.txt

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

                if [ ! -x "$GEN_SCRIPT" ]; then
                    whiptail --msgbox "错误: $GEN_SCRIPT 不存在或无执行权限\n\n请先安装配置生成脚本。" 10 60
                    continue
                fi

                if ! command -v nano >/dev/null 2>&1; then
                    whiptail --msgbox "错误: nano 编辑器未安装\n\n请先安装: apk add nano" 10 50
                    continue
                fi

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

                nano -w "$RAW_FILE"

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
