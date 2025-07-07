#!/bin/bash
# Скрипт для удаления пользователя OpenVPN

if [[ $# -eq 0 ]]; then
            echo "Использование: ./removeuser <username>"
                exit 1
fi

CLIENT=$1

# Проверка root-прав
if [[ "$EUID" -ne 0 ]]; then
            echo "Ошибка: этот скрипт должен запускаться с правами root"
                exit 1
fi

# Проверка, что OpenVPN установлен
if [[ ! -e /etc/openvpn/server.conf ]]; then
            echo "Ошибка: OpenVPN не установлен или не настроен"
                exit 1
fi

# Проверка существования пользователя
CLIENTEXISTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c -E "/CN=$CLIENT\$")
if [[ $CLIENTEXISTS == '0' ]]; then
            echo "Ошибка: пользователь '$CLIENT' не существует"
                exit 1
fi

# Отзыв сертификата
cd /etc/openvpn/easy-rsa/ || exit
./easyrsa --batch revoke "$CLIENT"
EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl

# Обновление CRL
rm -f /etc/openvpn/crl.pem
cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
chmod 644 /etc/openvpn/crl.pem

# Удаление конфигурационных файлов
find /home/ -maxdepth 2 -name "$CLIENT.ovpn" -delete
rm -f "/root/$CLIENT.ovpn"

# Удаление из ipp.txt (если используется)
sed -i "/^$CLIENT,.*/d" /etc/openvpn/ipp.txt

# Резервное копирование index.txt
cp /etc/openvpn/easy-rsa/pki/index.txt{,.bk}

echo "Пользователь $CLIENT успешно удален!"
echo "Не забудьте перезапустить OpenVPN для применения изменений: systemctl restart openvpn@server"