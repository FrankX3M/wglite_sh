#!/bin/bash

# Скрипт для проверки состояния WireGuard и клиентов
# Запускайте скрипт: ./check-wireguard.sh [имя_клиента]

CONTAINER_NAME="wireguard"

# Проверка запущен ли контейнер WireGuard
echo "=== Проверка статуса контейнера ==="
docker ps | grep $CONTAINER_NAME

# Проверка состояния WireGuard внутри контейнера
echo -e "\n=== Текущее состояние WireGuard (активные соединения) ==="
docker exec -it $CONTAINER_NAME wg show

# Проверка наличия созданных клиентов
echo -e "\n=== Список созданных клиентов ==="
docker exec -it $CONTAINER_NAME ls -la /config/peer_*

# Если указано имя клиента, отобразить его QR-код
if [ "$#" -eq 1 ]; then
    CLIENT_NAME=$1
    echo -e "\n=== QR-код для клиента '$CLIENT_NAME' ==="
    docker exec -it $CONTAINER_NAME /app/show-peer $CLIENT_NAME
    
    echo -e "\n=== Конфигурация клиента '$CLIENT_NAME' ==="
    docker exec -it $CONTAINER_NAME cat /config/peer_$CLIENT_NAME/peer_$CLIENT_NAME.conf
fi

# Проверка сетевой конфигурации
echo -e "\n=== Сетевые интерфейсы и маршруты WireGuard ==="
docker exec -it $CONTAINER_NAME ip a show wg0
docker exec -it $CONTAINER_NAME ip route | grep wg0

# Проверка логов контейнера
echo -e "\n=== Последние логи контейнера WireGuard ==="
docker logs --tail 20 $CONTAINER_NAME