#!/bin/bash

# Обновление системы
apt update && apt upgrade -y

# Установка необходимых пакетов
apt install -y sudo curl wget gnupg2 ca-certificates lsb-release ufw git

# Настройка файрвола
ufw allow 22/tcp      # или ваш custom порт SSH
ufw allow 443/tcp     # HTTPS для API Gateway
ufw allow 51820/udp   # WireGuard
ufw enable

# Подготовка к установке Docker
apt install -y apt-transport-https software-properties-common
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Обновление и установка Docker
apt update
apt install -y docker-ce docker-ce-cli containerd.io

# Включение автозапуска Docker
systemctl enable docker
systemctl start docker

# Установка Docker Compose
apt install -y docker-compose-plugin

# Проверка установки
docker --version
docker compose version

# Создание сети Docker
docker network create vpn-network


# Настройка SWAP
echo "Настройка SWAP-файла..."
# Проверка текущего состояния swap
free -h

# Создание swap-файла размером 2GB
fallocate -l 2G /swapfile
# Если fallocate не работает, раскомментировать следующую строку:
# dd if=/dev/zero of=/swapfile bs=1024 count=2097152

# Установка правильных разрешений
chmod 600 /swapfile

# Настройка файла как swap-пространства
mkswap /swapfile

# Активация swap
swapon /swapfile

# Настройка автоматической активации при загрузке
echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

# Настройка параметров использования swap
# Установка swappiness на 10 (лучше для серверов)
sysctl vm.swappiness=10
echo 'vm.swappiness=10' | tee -a /etc/sysctl.conf

# Настройка cache pressure
sysctl vm.vfs_cache_pressure=50
echo 'vm.vfs_cache_pressure=50' | tee -a /etc/sysctl.conf

# Проверка настройки swap
echo "Проверка настройки SWAP:"
free -h
swapon --show

echo "Настройка системы завершена!"



# Создание docker-compose.yml
cat > docker-compose.yml << 'EOL'
services:
  wireguard:
    image: linuxserver/wireguard
    container_name: wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Moscow
      - SERVERURL=auto
      - SERVERPORT=51820
      - PEERS=peer1  # Можно указать нужное количество пиров
      - PEERDNS=1.1.1.1,8.8.8.8  # Явно указываем DNS
      - INTERNAL_SUBNET=10.13.13.0
      - ALLOWEDIPS=0.0.0.0/0  # Разрешаем весь трафик через VPN
    volumes:
      - ./config:/config
    ports:
      - 51820:51820/udp
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1  # Явно включаем IP форвардинг
    restart: unless-stopped
    # Добавляем скрипты, которые будут выполняться при запуске
    command: |
      sh -c '
        # Запуск основного процесса
        /init &
        # Даем время на инициализацию WireGuard
        sleep 10
        # Настройка iptables
        iptables -t nat -F POSTROUTING
        iptables -t nat -A POSTROUTING -s 10.13.13.0/24 -o eth+ -j MASQUERADE
        iptables -F FORWARD
        iptables -A FORWARD -i wg0 -o eth+ -j ACCEPT
        iptables -A FORWARD -i eth+ -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
        # Установка MTU (может помочь с проблемами подключения)
        ip link set mtu 1420 dev wg0
        # Ожидание завершения основного процесса
        wait
      '
EOL

# Запуск контейнера
docker compose up -d

# очистка неиспользуемых контейнеров
docker system prune -a

# Создаем папки для конфигураций
mkdir -p /root/wglite_sh/config/wg_confs
mkdir -p /root/wglite_sh/config/peer_client1
chown -R 1000:1000 /root/wglite_sh/config

# создаем пир и выводим конфигурацию
chmod +x new_client.sh
./new_client.sh client1
./new_client.sh client2
./new_client.sh client3



# Генерация приватного ключа

# docker compose exec -it wireguard wg genkey
