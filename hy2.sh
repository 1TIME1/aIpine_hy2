#!/bin/bash
set -euo pipefail

# 安装依赖
apk add --no-cache --update wget curl openssl openrc

# 生成符合 RFC 4648 标准的 Base64 密码（24字符）
generate_random_password() {
  dd if=/dev/urandom bs=18 count=1 2>/dev/null | base64 | tr -d '\n' | tr +/ -_
}

GENPASS="$(generate_random_password)"

# 生成 Hysteria 2 配置文件
echo_hysteria_config_yaml() {
  cat << EOF
listen: :40443

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  users:
    - name: user
      password: $GENPASS

masquerade:
  type: http
  http:
    listen: :80
    handler: file_server
    path: /
    content: "Hello from Hysteria 2 Masquerade!"
EOF
}

# 生成 OpenRC 服务文件
echo_hysteria_autoStart() {
  cat << EOF
#!/sbin/openrc-run

name="hysteria"
description="Hysteria 2 VPN Service"

command="/usr/local/bin/hysteria"
command_args="server --config /etc/hysteria/config.yaml"
command_user="root:root"

pidfile="/var/run/\${name}.pid"
respawn_max=5
respawn_delay=10

depend() {
  need net
  use dns
}

start_pre() {
  checkpath -d -m 0755 /var/log/hysteria
}

logger -t "hysteria[\\\${RC_SVCNAME}]" -p local0.info
EOF
}

# 下载官方二进制文件（指定 Hysteria 2 版本）
HYSTERIA_VERSION="v2.2.2"
HYSTERIA_URL="https://github.com/apernet/hysteria/releases/download/${HYSTERIA_VERSION}/hysteria-linux-amd64"
wget --show-progress -qO /usr/local/bin/hysteria "$HYSTERIA_URL" || {
  echo "错误：文件下载失败！" >&2
  exit 1
}
chmod +x /usr/local/bin/hysteria

# 创建配置目录
mkdir -p /etc/hysteria

# 生成 ECDSA 证书（P-256 曲线，有效期 100 年）
openssl req -x509 -nodes \
  -newkey ec:<(openssl ecparam -name prime256v1) \
  -keyout /etc/hysteria/server.key \
  -out /etc/hysteria/server.crt \
  -subj "/CN=www.bing.com" \
  -days 36500 || {
  echo "错误：证书生成失败！" >&2
  exit 1
}

# 写入配置文件
echo_hysteria_config_yaml > /etc/hysteria/config.yaml

# 配置服务管理
echo_hysteria_autoStart > /etc/init.d/hysteria
chmod 755 /etc/init.d/hysteria

# 启用并启动服务
rc-update add hysteria default >/dev/null 2>&1
if ! service hysteria start; then
  echo "错误：服务启动失败！检查配置后重试" >&2
  exit 1
fi

# 验证服务状态
sleep 2
service hysteria status || {
  echo "警告：服务似乎未正常运行，检查日志：journalctl -u hysteria" >&2
}

# 显示安装结果
cat << EOF

 /$$   /$$ /$$     /$$/$$$$$$  /$$$$$$$$/$$$$$$$$ /$$$$$$$  /$$$$$$  /$$$$$$   /$$$$$$ 
| $$  | $$|  $$   /$$/$$__  $$|__  $$__/ $$_____/| $$__  $$|_  $$_/ /$$__  $$ /$$__  $$
| $$  | $$ \  $$ /$$/ $$  \__/   | $$  | $$      | $$  \ $$  | $$  | $$  \ $$|__/  \ $$
| $$$$$$$$  \  $$$$/|  $$$$$$    | $$  | $$$$$   | $$$$$$$/  | $$  | $$$$$$$$  /$$$$$$/
| $$__  $$   \  $$/  \____  $$   | $$  | $$__/   | $$__  $$  | $$  | $$__  $$ /$$____/ 
| $$  | $$    | $$   /$$  \ $$   | $$  | $$      | $$  \ $$  | $$  | $$  | $$| $$      
| $$  | $$    | $$  |  $$$$$$/   | $$  | $$$$$$$$| $$  | $$ /$$$$$$| $$  | $$| $$$$$$$$
|__/  |__/    |__/   \______/    |__/  |________/|__/  |__/|______/|__/  |__/|________/
                                                                                                                                                                        

✅ 安装完成！配置文件路径：/etc/hysteria/config.yaml

▸ 服务器端口：40443/udp
▸ 认证用户：user
▸ 认证密码：${GENPASS}
▸ TLS SNI：www.bing.com
▸ 伪装站点：监听在 80 端口的 HTTP 服务

📌 客户端配置示例（Hysteria 2）：
{
  "server": "your_ip:40443",
  "auth": {
    "user": "user",
    "password": "${GENPASS}"
  },
  "tls": {
    "sni": "www.bing.com",
    "insecure": true
  },
  // ...其他客户端参数
}

🛠 管理命令：
service hysteria status  # 查看状态
service hysteria restart # 重启服务
journalctl -u hysteria   # 查看日志

EOF
