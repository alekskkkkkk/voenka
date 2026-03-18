#!/bin/bash
chmod +x *.sh
chmod +x ./kr_vko/GenTargets.sh
./kr_vko/GenTargets.sh
./data.sh &
./kp.sh &
./rls2.sh &
./zrdn1.sh &
echo "Система ВКО активирована. Смотри логи в vko_main.log"