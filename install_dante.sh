#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Dante SOCKS5 Proxy Installer with Username/Password Auth
# ─────────────────────────────────────────────────────────────

# Требуется запуск от root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Запустите скрипт от имени root." >&2
  exit 1
fi

# --- 1) Спрашиваем учётные данные для прокси ---
read -p "Введите имя пользователя для прокси: " PROXY_USER
read -s -p "Введите пароль для прокси: " PROXY_PASS
echo

# --- 2) Устанавливаем пакет dante-server ---
echo "🛠 Устанавливаем dante-server..."
apt update
apt install -y dante-server

# --- 3) Создаём системного юзера без шелла (если ещё нет) ---
if ! id "$PROXY_USER" &>/dev/null; then
  echo "👤 Создаём пользователя $PROXY_USER..."
  useradd -M -s /usr/sbin/nologin "$PROXY_USER"
fi

# Меняем пароль
echo "${PROXY_USER}:${PROXY_PASS}" | chpasswd

# --- 4) Определяем внешний интерфейс автоматически ---
EXTERNAL_IFACE=$(ip route show default | awk '/default/ {print $5}')
if [[ -z "$EXTERNAL_IFACE" ]]; then
  EXTERNAL_IFACE="eth0"
fi

# --- 5) Генерируем конфиг /etc/danted.conf ---
echo "📄 Пишем конфиг /etc/danted.conf..."
cat > /etc/danted.conf <<EOF
# Dante SOCKS5 Proxy with username/password authentication
logoutput: syslog

# слушать на всех адресах, порт 1080
internal: 0.0.0.0 port = 1080
external: $EXTERNAL_IFACE

# аутентификация
method: username
user.privileged: root
user.notprivileged: nobody

# разрешаем логиниться только по username/password
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    method: username
    log: connect error
}

pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    method: username
    log: connect error
}
EOF

# --- 6) Настраиваем брандмауэр (ufw или iptables) ---
echo "🔒 Настраиваем брандмауэр на порт 1080..."
if command -v ufw &>/dev/null; then
  ufw allow 1080/tcp
else
  iptables -C INPUT -p tcp --dport 1080 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
fi

# --- 7) Перезапуск и автозапуск сервиса ---
echo "🔁 Перезапускаем и включаем danted..."
systemctl restart danted
systemctl enable danted

# --- 8) Итог ---
cat <<EOS

✅ Dante SOCKS5 установлен и запущен!

Подключайтесь из браузера или любого клиента SOCKS5:

  Host:  your.server.com  
  Port:  1080  
  User:  $PROXY_USER  
  Pass:  <тот, что вы задали>

Не забудьте в клиенте включить Proxy-DNS (если есть такая опция).

EOS
