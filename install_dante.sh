#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────
# Dante SOCKS5 Installer (Debian/Ubuntu) with PAM Username Auth
# ────────────────────────────────────────────────────────────

# 1) Проверка прав
if [[ $EUID -ne 0 ]]; then
  echo "❌ Этот скрипт надо запускать от root." >&2
  exit 1
fi

# 2) Запросим учётку для прокси
read -p "Введите имя прокси-пользователя: " PROXY_USER
read -s -p "Введите пароль для $PROXY_USER: " PROXY_PASS
echo

# 3) Установка Dante
echo "🛠  Устанавливаем dante-server..."
apt update
apt install -y dante-server

# 4) Создание системного юзера (без shell’а)
if ! id "$PROXY_USER" &>/dev/null; then
  echo "👤  Создаём пользователя $PROXY_USER..."
  useradd -M -s /usr/sbin/nologin "$PROXY_USER"
fi
echo "${PROXY_USER}:${PROXY_PASS}" | chpasswd

# 5) Определяем внешний интерфейс
EXT_IFACE=$(ip route get 8.8.8.8 2>/dev/null \
  | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')
if [[ -z "$EXT_IFACE" ]]; then
  echo "⚠️  Не удалось определить внешний интерфейс, используем eth0"
  EXT_IFACE="eth0"
else
  echo "🌐  Внешний интерфейс: $EXT_IFACE"
fi

# 6) Пишем корректный конфиг
echo "📄  Записываем /etc/danted.conf..."
cat > /etc/danted.conf <<EOF
# Dante SOCKS5 Proxy — PAM username/password auth
logoutput: syslog

# на каком адресе/порту слушаем
internal: 0.0.0.0 port = 1080

# через какой интерфейс выходим
external: $EXT_IFACE

# глобальные методы аутентификации:
#   clientmethod — проверка до SOCKS (rfc931, pam)
#   socksmethod — после рукопожатия (pam.username, username, none…)
clientmethod: pam          # допустимо: rfc931, pam :contentReference[oaicite:0]{index=0}
socksmethod: pam.username  # вместо deprecated pam → pam.username :contentReference[oaicite:1]{index=1}

# под кем запускаем дочерние процессы
user.privileged: root
user.notprivileged: nobody

# правила доступа:
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}

pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect error
}
EOF

# 7) Открываем порт в фаерволе
echo "🔒  Открываем порт 1080..."
if command -v ufw &>/dev/null; then
  ufw allow 1080/tcp
else
  iptables -C INPUT -p tcp --dport 1080 -j ACCEPT 2>/dev/null \
    || iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
fi

# 8) Перезапуск и автозапуск
echo "🔁  Перезапускаем и включаем danted..."
systemctl daemon-reload
systemctl restart danted
systemctl enable danted

# 9) Готово
cat <<INFO

✅  Установка завершена!

SOCKS5 proxy слушает на порту 1080 с PAM-аутентификацией:

  • Host: your.server.com  
  • Port: 1080  
  • User: $PROXY_USER  
  • Pass: тот пароль, что вы задали  

Проверка из клиента:

  curl --socks5-hostname \
       $PROXY_USER:$PROXY_PASS@127.0.0.1:1080 \
       https://ifconfig.me

INFO
