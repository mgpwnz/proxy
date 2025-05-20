#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────────
# Dante SOCKS5 Proxy Installer with Username/Password (PAM) Auth
# Supported on Debian/Ubuntu
# ────────────────────────────────────────────────────────────────────

# 1) Проверяем, что скрипт запущен от root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Пожалуйста, запустите скрипт от root." >&2
  exit 1
fi

# 2) Спрашиваем имя нового прокси-пользователя и пароль
read -p "Введите имя прокси-пользователя: " PROXY_USER
read -s -p "Введите пароль для $PROXY_USER: " PROXY_PASS
echo

# 3) Устанавливаем dante-server
echo "🛠 Устанавливаем пакет dante-server..."
apt update
apt install -y dante-server

# 4) Создаём системного пользователя без shell’а (если ещё нет)
if ! id "$PROXY_USER" &>/dev/null; then
  echo "👤 Создаём пользователя $PROXY_USER..."
  useradd -M -s /usr/sbin/nologin "$PROXY_USER"
fi

# 5) Устанавливаем пароль
echo "${PROXY_USER}:${PROXY_PASS}" | chpasswd

# 6) Определяем внешний интерфейс (по умолчанию — dev по маршруту к 8.8.8.8)
EXT_IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')
if [[ -z "$EXT_IFACE" ]]; then
  echo "⚠️ Не удалось определить внешний интерфейс, используем eth0"
  EXT_IFACE="eth0"
else
  echo "🌐 Внешний интерфейс определён: $EXT_IFACE"
fi

# 7) Пишем конфиг /etc/danted.conf
echo "📄 Записываем /etc/danted.conf..."
cat > /etc/danted.conf <<EOF
# Dante SOCKS5 Proxy with PAM authentication
logoutput: syslog

# на каком адресе/порту слушаем SOCKS-клиентов
internal: 0.0.0.0 port = 1080

# какой внешний интерфейс использовать для исходящих соединений
external: $EXT_IFACE

# методы аутентификации
socksmethod: username
clientmethod: pam

# под кем запускаем дочерние процессы
user.privileged: root
user.notprivileged: nobody

# разрешаем клиентам проходить рукопожатие и аутентификацию
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}

# разрешаем проксировать TCP и UDP после успешной аутентификации
pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect error
}
EOF

# 8) Настраиваем фаервол (ufw или iptables)
echo "🔒 Открываем порт 1080 в фаерволе..."
if command -v ufw &>/dev/null; then
  ufw allow 1080/tcp
else
  # проверяем, нет ли уже такого правила
  if ! iptables -C INPUT -p tcp --dport 1080 -j ACCEPT &>/dev/null; then
    iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
  fi
fi

# 9) Перезапускаем и включаем сервис
echo "🔁 Перезапускаем danted и включаем автозапуск..."
systemctl daemon-reload
systemctl restart danted
systemctl enable danted

# 10) Итог
cat <<EOS

✅ Установка завершена!

Теперь ваш сервер слушает SOCKS5-прокси на порту 1080 с аутентификацией через PAM.

Подключение из клиента (пример curl):

  curl --socks5-hostname \
       ${PROXY_USER}:${PROXY_PASS}@your.server.com:1080 \
       https://ifconfig.me

В браузере (SwitchyOmega и т.п.) укажите профиль:

  • Protocol: SOCKS5  
  • Host:     your.server.com  
  • Port:     1080  
  • Username: $PROXY_USER  
  • Password: (тот, что вы ввели)

EOS
