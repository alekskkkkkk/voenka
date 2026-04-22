#!/bin/bash

# Очистка общих логов и временных файлов перед стартом
> /tmp/vko_messages.log
rm -rf /tmp/GenTargets/Destroy/* 2>/dev/null
mkdir -p /tmp/GenTargets/Destroy

echo "=== ЗАПУСК СИСТЕМЫ ВКО ==="
echo "Логи очищены."

# Запускаем РЛС в фоновом режиме
./rls1.sh &
./rls2.sh &
./rls3.sh &

./zrdn1.sh &
./zrdn2.sh &
./zrdn3.sh &

./spro.sh &

echo "Система ВКО (РЛС, ЗРДН, СПРО) полностью развернута в фоне."
echo "Для просмотра логов используй: tail -f /tmp/vko_messages.log"