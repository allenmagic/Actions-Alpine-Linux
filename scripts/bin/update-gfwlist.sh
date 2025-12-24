#!/bin/sh

# 配置变量
GFW_URL="https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt"
CONF_DIR="/etc/dnsmasq.d"
CONF_FILE="$CONF_DIR/90-gfwlist-auto.conf"
NFT_SET_NAME="proxy_set"

# 1. 确认配置目录是否存在，不存在则创建
if [ ! -d "$CONF_DIR" ]; then
    echo "目录 $CONF_DIR 不存在，正在创建..."
    mkdir -p "$CONF_DIR"
fi

echo "正在从远程获取 GFWList..."
# 使用 curl 下载并 base64 解码，增加重试机制
curl -sS --retry 3 $GFW_URL | base64 -d > /tmp/gfwlist.raw

if [ $? -ne 0 ]; then
    echo "下载或解码失败，请检查网络。"
    exit 1
fi

# 2. 过滤域名并生成 dnsmasq 规则
# 优化逻辑：每个域名同时生成 8.8.8.8 和 1.1.1.1 的 server 记录
# 同时写入 nftset 记录到 singbox 表的 proxy_set
echo "正在解析域名并生成规则..."

grep -vE '^\!|@@|\[|^$' /tmp/gfwlist.raw | \
    sed -E 's#^(\|\||\|)##; s#https?://##; s#/.*##; s#^\.##' | \
    sort -u | grep "\." | \
    awk -v set=$NFT_SET_NAME '{
        print "server=/"$1"/8.8.8.8";
        print "server=/"$1"/1.1.1.1";
        print "nftset=/"$1"/4#inet#singbox#"set
    }' > $CONF_FILE

echo "GFWList 已成功更新至 $CONF_FILE"
echo "正在重启 dnsmasq 以应用更改..."
rc-service dnsmasq restart

# 清理临时文件
rm /tmp/gfwlist.raw