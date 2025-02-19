#!/bin/bash

# Удаление переменных окружения из текущей сессии
unset http_proxy
unset https_proxy
unset ftp_proxy
unset no_proxy

# Удаление из ~/.bashrc и ~/.profile
sed -i '/export http_proxy/d' ~/.bashrc
sed -i '/export https_proxy/d' ~/.bashrc
sed -i '/export ftp_proxy/d' ~/.bashrc
sed -i '/export no_proxy/d' ~/.bashrc

sed -i '/export http_proxy/d' ~/.profile
sed -i '/export https_proxy/d' ~/.profile
sed -i '/export ftp_proxy/d' ~/.profile
sed -i '/export no_proxy/d' ~/.profile

# Удаление конфигурации APT
sudo rm -f /etc/apt/apt.conf.d/95proxies

# Удаление настроек Wget
sudo sed -i '/http_proxy/d' /etc/wgetrc
sudo sed -i '/https_proxy/d' /etc/wgetrc
sudo sed -i '/use_proxy/d' /etc/wgetrc

# Удаление настроек Curl
rm -f ~/.curlrc

# Применение изменений
source ~/.bashrc

echo "Все настройки прокси удалены."

