#!/bin/bash


SOURCE_DIR=$(dirname "$(readlink -f "$0")")


> /tmp/vko_messages.log
> "$SOURCE_DIR/vko_messages.log"

rm -f "$SOURCE_DIR"/*_enc.log
rm -rf /tmp/GenTargets/Destroy/* 2>/dev/null
mkdir -p /tmp/GenTargets/Destroy

echo "=== ЗАПУСК СИСТЕМЫ ВКО ==="
echo "Логи очищены."


./rls1.sh &
./rls2.sh &
./rls3.sh &


./zrdn1.sh &
./zrdn2.sh &
./zrdn3.sh &


./spro.sh &

echo "Система ВКО (РЛС, ЗРДН, СПРО) полностью развернута в фоне."
