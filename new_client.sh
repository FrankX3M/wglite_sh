#!/bin/bash

# Скрипт для добавления нового клиента WireGuard через хост-систему
# Запускайте скрипт: ./host-add-client.sh <имя_клиента>

# Проверка наличия аргумента с именем клиента
if [ "$#" -ne 1 ]; then
    echo "Использование: $0 <имя_клиента>"
    exit 1
fi

CLIENT_NAME=$1
CONTAINER_NAME="wireguard"
CONFIG_DIR="/root/wglite_sh/config"

# Проверка существования контейнера
if ! docker ps -q -f name=$CONTAINER_NAME | grep -q .; then
    echo "Ошибка: контейнер '$CONTAINER_NAME' не найден или не запущен."
    exit 1
fi

echo "Создание клиента '$CLIENT_NAME'..."

# Создаем директории на хосте
mkdir -p $CONFIG_DIR/wg_confs
mkdir -p $CONFIG_DIR/peer_$CLIENT_NAME

# Получаем публичный ключ сервера
SERVER_PUBLIC_KEY=$(docker exec -it $CONTAINER_NAME wg show wg0 public-key)
SERVER_IP=$(curl -s ifconfig.me)
SERVER_PORT=51820  # Порт по умолчанию для WireGuard

# Генерируем приватный и публичный ключи для клиента
CLIENT_PRIVATE_KEY=$(docker exec -it $CONTAINER_NAME wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | docker exec -i $CONTAINER_NAME wg pubkey)
PRESHARED_KEY=$(docker exec -it $CONTAINER_NAME wg genpsk)

# Определяем IP для клиента (ищем последний используемый IP и увеличиваем на 1)
LAST_IP=$(docker exec -it $CONTAINER_NAME wg show wg0 | grep "allowed ips" | grep -oE "10\.13\.13\.[0-9]+" | sort -t. -k4,4n | tail -n1)
if [ -z "$LAST_IP" ]; then
    # Если нет других пиров, начинаем с .2 (сервер обычно использует .1)
    CLIENT_IP="10.13.13.2"
else
    LAST_OCTET=$(echo $LAST_IP | cut -d. -f4)
    NEXT_OCTET=$((LAST_OCTET + 1))
    CLIENT_IP="10.13.13.$NEXT_OCTET"
fi

# Создаем конфигурационный файл для клиента
CLIENT_CONFIG="[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
Endpoint = $SERVER_IP:$SERVER_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25"

# Записываем конфигурацию в файл на хосте
echo "$CLIENT_CONFIG" > $CONFIG_DIR/peer_$CLIENT_NAME/peer_$CLIENT_NAME.conf

# Получаем текущую конфигурацию сервера или создаем новую
if [ ! -f "$CONFIG_DIR/wg_confs/wg0.conf" ]; then
    # Если файла нет, создаем его на основе текущей конфигурации
    docker exec -it $CONTAINER_NAME wg showconf wg0 > $CONFIG_DIR/wg_confs/wg0.conf

    # Если команда не вернула результат, создаем базовую конфигурацию
    if [ ! -s "$CONFIG_DIR/wg_confs/wg0.conf" ]; then
        echo "[Interface]
ListenPort = 51820
PrivateKey = $(docker exec -it $CONTAINER_NAME wg genkey)
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth+ -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth+ -j MASQUERADE" > $CONFIG_DIR/wg_confs/wg0.conf
    fi
fi

# Добавляем запись о пире в конфигурацию сервера
PEER_CONFIG="
# peer_$CLIENT_NAME
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = $CLIENT_IP/32"

echo "$PEER_CONFIG" >> $CONFIG_DIR/wg_confs/wg0.conf

# Устанавливаем правильные права доступа
chown -R 1000:1000 $CONFIG_DIR

# Добавляем пир непосредственно в работающий интерфейс
docker exec -it $CONTAINER_NAME wg set wg0 peer $CLIENT_PUBLIC_KEY preshared-key <(echo $PRESHARED_KEY) allowed-ips $CLIENT_IP/32

# Обновляем маршрутизацию для нового IP
docker exec -it $CONTAINER_NAME ip -4 route add $CLIENT_IP/32 dev wg0 2>/dev/null || true

# Генерируем QR-код из конфигурации клиента
echo "QR-код для клиента '$CLIENT_NAME':"
cat $CONFIG_DIR/peer_$CLIENT_NAME/peer_$CLIENT_NAME.conf | docker exec -i $CONTAINER_NAME qrencode -t ansiutf8

echo "Конфигурация для клиента '$CLIENT_NAME' создана."
echo "Файл конфигурации находится в: $CONFIG_DIR/peer_$CLIENT_NAME/peer_$CLIENT_NAME.conf"
echo "Для отображения QR-кода используйте:"
echo "cat $CONFIG_DIR/peer_$CLIENT_NAME/peer_$CLIENT_NAME.conf | docker exec -i $CONTAINER_NAME qrencode -t ansiutf8"

# Проверка, что файл конфигурации был успешно создан
if [ -f "$CONFIG_DIR/peer_$CLIENT_NAME/peer_$CLIENT_NAME.conf" ]; then
    echo "✅ Файл конфигурации успешно создан."
else
    echo "❌ Ошибка: Файл конфигурации не был создан."
fi