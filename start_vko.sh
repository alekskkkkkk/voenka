#!/bin/bash

SOURCE_DIR=$(dirname "$(readlink -f "$0")")

# --- ОЧИСТКА СТАРЫХ ДАННЫХ И ЛОГОВ ---
> /tmp/vko_messages.log
> "$SOURCE_DIR/vko_messages.log"
> "$SOURCE_DIR/vko_decrypted_all.log" # Очищаем глобальный лог КП

# Удаляем старые буферы сообщений (новая архитектура)
rm -f "$SOURCE_DIR"/*.msg 
rm -f "$SOURCE_DIR"/*.hb  # <--- Добавить вот эту строчку
rm -rf /tmp/GenTargets/Destroy/* 2>/dev/null
mkdir -p /tmp/GenTargets/Destroy

echo "=== ЗАПУСК СИСТЕМЫ ВКО ==="
echo "Логи и буферы очищены."

# --- ЗАПУСК ГЕНЕРАТОРА ЦЕЛЕЙ ---
# Предполагается, что папка kr_vko находится там же, откуда запускается скрипт.
# Если GenTargets.sh лежит в той же папке, что и этот скрипт, путь будет: "$SOURCE_DIR/GenTargets.sh" &
if [ -f "$SOURCE_DIR/kr_vko/GenTargets.sh" ]; then
    "$SOURCE_DIR/kr_vko/GenTargets.sh" &
    echo "[OK] Генератор целей запущен."
elif [ -f "$SOURCE_DIR/GenTargets.sh" ]; then
    "$SOURCE_DIR/GenTargets.sh" &
    echo "[OK] Генератор целей запущен."
else
    echo "[ВНИМАНИЕ] Скрипт генератора целей (GenTargets.sh) не найден!"
fi

# --- ЗАПУСК БОЕВЫХ МОДУЛЕЙ ---
./rls1.sh &
./rls2.sh &
./rls3.sh &

./zrdn1.sh &
./zrdn2.sh &
./zrdn3.sh &

./spro.sh &

echo "Система ВКО (РЛС, ЗРДН, СПРО) полностью развернута в фоне."
echo "Запустите ./kp.sh для открытия Командного пункта."