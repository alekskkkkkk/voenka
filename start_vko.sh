#!/bin/bash

# Определяем директорию, где лежит скрипт
SOURCE_DIR=$(dirname "$(readlink -f "$0")")

# Очистка общих логов и временных файлов перед стартом
> /tmp/vko_messages.log
> "$SOURCE_DIR/vko_messages.log"

rm -rf /tmp/GenTargets/Destroy/* 2>/dev/null
mkdir -p /tmp/GenTargets/Destroy

echo "=== ЗАПУСК СИСТЕМЫ ВКО ==="
echo "Логи очищены."

# Запускаем РЛС в фоновом режиме
./rls1.sh &
./rls2.sh &
./rls3.sh &

# Запускаем ЗРДН в фоновом режиме
./zrdn1.sh &
./zrdn2.sh &
./zrdn3.sh &

# Запускаем СПРО в фоновом режиме
./spro.sh &

echo "Система ВКО (РЛС, ЗРДН, СПРО) полностью развернута в фоне."
echo "Для просмотра логов используй: tail -f vko_messages.log"