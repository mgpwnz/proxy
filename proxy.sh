#!/bin/bash

# Запрос у пользователя ввода прокси в формате IP:PORT:USERNAME:PASSWORD
echo "Введите прокси (формат: IP:PORT:USERNAME:PASSWORD):"
read PROXY_INPUT

# Разбиваем строку на переменные
IP=$(echo $PROXY_INPUT | cut -d':' -f1)
PORT=$(echo $PROXY_INPUT | cut -d':' -f2)
USERNAME=$(echo $PROXY_INPUT | cut -d':' -f3)
PASSWORD=$(echo $PROXY_INPUT | cut -d':' -f4)

# Формируем строку прокси
PROXY_SERVER="http://$USERNAME:$PASSWORD@$IP:$PORT"
NO_PROXY_LIST="localhost,127.0.0.1,::1"

# Установка переменных окружения
export http_proxy="$PROXY_SERVER"
export https_proxy="$PROXY_SERVER"
export ftp_proxy="$PROXY_SERVER"
export no_proxy="$NO_PROXY_LIST"

# Добавление в ~/.bashrc и ~/.profile для автоматического применения при запуске
echo "export http_proxy=\"$PROXY_SERVER\"" >> ~/.bashrc
echo "export https_proxy=\"$PROXY_SERVER\"" >> ~/.bashrc
echo "export ftp_proxy=\"$PROXY_SERVER\"" >> ~/.bashrc
echo "export no_proxy=\"$NO_PROXY_LIST\"" >> ~/.bashrc

echo "export http_proxy=\"$PROXY_SERVER\"" >> ~/.profile
echo "export https_proxy=\"$PROXY_SERVER\"" >> ~/.profile
echo "export ftp_proxy=\"$PROXY_SERVER\"" >> ~/.profile
echo "export no_proxy=\"$NO_PROXY_LIST\"" >> ~/.profile

# Настройка APT прокси
APT_PROXY_FILE="/etc/apt/apt.conf.d/95proxies"
echo "Acquire::http::Proxy \"$PROXY_SERVER\";" | sudo tee $APT_PROXY_FILE > /dev/null
echo "Acquire::https::Proxy \"$PROXY_SERVER\";" | sudo tee -a $APT_PROXY_FILE > /dev/null

# Настройка Wget
WGET_CONFIG="/etc/wgetrc"
sudo sed -i "s|#http_proxy =.*|http_proxy = $PROXY_SERVER|g" $WGET_CONFIG
sudo sed -i "s|#https_proxy =.*|https_proxy = $PROXY_SERVER|g" $WGET_CONFIG
sudo sed -i "s|#use_proxy = on|use_proxy = on|g" $WGET_CONFIG

# Настройка Curl
CURL_CONFIG="$HOME/.curlrc"
touch "$CURL_CONFIG"  # Создаем файл, если его нет
echo "proxy = $PROXY_SERVER" >> "$CURL_CONFIG"

# Применение настроек
source ~/.bashrc

echo "Прокси установлен по умолчанию для всей системы."
