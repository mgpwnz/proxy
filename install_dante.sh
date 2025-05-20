#!/usr/bin/env bash
set -euo pipefail

# ───────────────────────────────────────────────────────────────
# Dante SOCKS5 Proxy Installer with Username/Password Auth
# На Debian/Ubuntu — вместо PAM используем 'username' метод
# ───────────────────────────────────────────────────────────────

# 1) Проверка, что скрипт запущен от root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Запустите, пожалуйста, от root." >&2
  exit 1
fi

# 2) Спрашиваем учётку для прокси
read -p "Введите имя прокси-пользователя: " PROXY_USER
read -s -p "Введите пароль для $PROXY_USER: " PROXY_PASS
echo

# 3) Устанавливаем dante-server
echo "🛠 Устанавливаем dante-server..."
apt update
apt install -y dante-server

# 4) Создаём пользователя без shell’а (если ещё нет)
if ! id "$PROXY_USER" &>/dev/null; then
  echo "👤 Создаём system-юзера $PROXY_USER..."
  useradd -M -s /usr/sbin/nologin "$PROXY_USER"
fi
echo "${PROXY_USER}:${PROXY_PASS}" | chpasswd

# 5) Определяем внешний интерфейс
EXT_IFACE=$(ip route get 8.8.8.8 2>/dev/null \
  | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')
if [[ -z "$EXT_IFACE" ]]; then
  echo "⚠️ Не определён внешний интерфейс, ставим eth0"
  EXT_IFACE="eth0"
else
  echo "🌐 Внешний интерфейс: $EXT_IFACE"
fi

# 6) Генерируем /etc/danted.conf
echo "📄 Пишем /etc/danted.conf..."
cat > /etc/danted.conf <<EOF
# Dante SOCKS5 Proxy — Username authentication
logoutput: syslog

# слушаем все адреса на 1080
internal: 0.0.0.0 port = 1080

# выход через внешний интерфейс
external: $EXT_IFACE

# clientmethod: для client-rules (до SOCKS-handshake) — none
clientmethod: none

# socksmethod: аутентификация внутри SOCKS-handshake
# supported: username, none, rfc931, gssapi, pam.*
socksmethod: username

# run as root → drop to nobody
user.privileged: root
user.notprivileged: nobody

# client pass — разрешить рукопожатие (и логин)
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}

# pass — проксировать TCP/UDP после аутентификации
pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect error
}
EOF

# 7) Открываем порт в фаерволе
echo "🔒 Открываем TCP/1080..."
if command -v ufw &>/dev/null; then
  ufw allow 1080/tcp
else
  iptables -C INPUT -p tcp --dport 1080 -j ACCEPT 2>/dev/null \
    || iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
fi

# 8) Перезапускаем и включаем сервис
echo "🔁 Перезапускаем и включаем danted..."
systemctl daemon-reload
systemctl restart danted
systemctl enable danted

# 9) Финал
cat <<EOS

✅ Установка завершена!

SOCKS5 proxy с проверкой username/password слушает на 1080 порту.

Подключение:

  Host:     your.server.com  
  Port:     1080  
  Username: $PROXY_USER  
  Password: (тот, что вы ввели)  

Проверка из Linux/WSL:

  curl --socks5-hostname \
       $PROXY_USER:$PROXY_PASS@127.0.0.1:1080 \
       https://ifconfig.me

В браузере (SwitchyOmega):

  • Protocol: SOCKS5  
  • Server:   your.server.com  
  • Port:     1080  
  • Username: $PROXY_USER  
  • Password: (ваш пароль)

EOS
