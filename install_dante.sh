#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────
# Dante SOCKS5 Installer (Debian/Ubuntu) with Username/Password
# ────────────────────────────────────────────────────────────

# 1) Только под root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Запустите от root." >&2
  exit 1
fi

# 2) Читаем имя и пароль для прокси-юзера
read -p "Имя прокси-пользователя: " PROXY_USER
read -s -p "Пароль: " PROXY_PASS
echo

# 3) Устанавливаем пакет
apt update
apt install -y dante-server

# 4) Создаём юзера без шелла (если нет)
if ! id "$PROXY_USER" &>/dev/null; then
  useradd -M -s /usr/sbin/nologin "$PROXY_USER"
fi
echo "${PROXY_USER}:${PROXY_PASS}" | chpasswd

# 5) Определяем внешний интерфейс
EXT_IFACE=$(ip route get 8.8.8.8 2>/dev/null \
  | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')
: "${EXT_IFACE:=eth0}"   # по умолчанию eth0

# 6) Пишем правильный конфиг
cat > /etc/danted.conf <<EOF
# Dante SOCKS5 Proxy — Username auth
logoutput: syslog

internal: 0.0.0.0 port = 1080
external: $EXT_IFACE

clientmethod: none
socksmethod: username

user.privileged: root
user.notprivileged: nobody

# Рукопожатие
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}

# Проксируем после аутентификации
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect error
}

# Всё остальное блокируем
socks block {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}
EOF

# 7) Открываем порт 1080
if command -v ufw &>/dev/null; then
  ufw allow 1080/tcp
else
  iptables -C INPUT -p tcp --dport 1080 -j ACCEPT 2>/dev/null \
    || iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
fi

# 8) Перезапуск
systemctl daemon-reload
systemctl restart danted
systemctl enable danted

# 9) Готово
cat <<MSG

✅ Dante запущен!

Подключайтесь так (пример curl):

curl --socks5-hostname \
     ${PROXY_USER}:${PROXY_PASS}@127.0.0.1:1080 \
     https://ifconfig.me

Если клиент не посылает USERNAME/PASSWORD в handshake, вы снова увидите 
«client offered no acceptable authentication method» — значит, надо 
включить в клиенте именно SOCKS5+Auth, а не «без пароля».

MSG
