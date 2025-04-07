# Создание правильной структуры для peer1
# Остановите контейнер перед запуском этого скрипта
# docker stop wireguard

# 1. Создаем директорию для peer1 (если она еще не существует)
mkdir -p ./config/wg_confs/peer_peer1

# 2. Извлекаем информацию из существующей конфигурации
SERVER_PRIVKEY=$(grep "PrivateKey" ./config/wg_confs/wg0.conf | cut -d ' ' -f 3)
SERVER_PUBKEY=$(echo "$SERVER_PRIVKEY" | wg pubkey)  # Требуется утилита wg на хост-системе
CLIENT_PUBKEY=$(grep -A 2 "# peer1" ./config/wg_confs/wg0.conf | grep "PublicKey" | cut -d ' ' -f 3)
CLIENT_PSK=$(grep -A 3 "# peer1" ./config/wg_confs/wg0.conf | grep "PresharedKey" | cut -d ' ' -f 3)
SERVER_IP=$(curl -s ifconfig.me)

# Если у вас нет утилиты wg на хост-системе, можно использовать контейнер
# SERVER_PUBKEY=$(docker run --rm -v ./config:/config linuxserver/wireguard sh -c "echo '$SERVER_PRIVKEY' | wg pubkey")

# 3. Генерируем приватный ключ для клиента, если он отсутствует
# Примечание: нужно заменить это на ваш существующий приватный ключ, если он у вас есть
# В противном случае, старый ключ будет заменен новым
CLIENT_PRIVKEY=$(wg genkey)  # Требуется утилита wg на хост-системе
# CLIENT_PRIVKEY=$(docker run --rm linuxserver/wireguard wg genkey)  # Альтернатива через контейнер

# 4. Создаем конфигурационный файл клиента
cat > ./config/wg_confs/peer_peer1/peer_peer1.conf << EOF
[Interface]
PrivateKey = $CLIENT_PRIVKEY
Address = 10.13.13.2/32
DNS = 10.13.13.1

[Peer]
PublicKey = $SERVER_PUBKEY
PresharedKey = $CLIENT_PSK
Endpoint = $SERVER_IP:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

# 5. Установите правильные разрешения на файл
chmod 600 ./config/wg_confs/peer_peer1/peer_peer1.conf

echo "Клиент peer1 настроен. Запустите контейнер: docker start wireguard"
echo "После запуска вы можете получить QR-код командой: docker exec -it wireguard /app/show-peer peer1"