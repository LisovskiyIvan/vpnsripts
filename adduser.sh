#!/bin/bash
# Скрипт для добавления нового пользователя OpenVPN с автоматической настройкой DNS

if [[ $# -eq 0 ]]; then
    echo "Использование: $0 <username>"
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

# Проверка имени пользователя
if [[ ! $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Ошибка: имя пользователя может содержать только буквы, цифры, подчеркивание и дефис"
    exit 1
fi

# Проверка существования пользователя
CLIENTEXISTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c -E "/CN=$CLIENT\$")
if [[ $CLIENTEXISTS == '1' ]]; then
    echo "Ошибка: пользователь '$CLIENT' уже существует"
    exit 1
fi

# Проверка существования шаблона
if [[ ! -f /etc/openvpn/client-template.txt ]]; then
    echo "Ошибка: файл шаблона /etc/openvpn/client-template.txt не найден"
    exit 1
fi

# Создание пользователя
cd /etc/openvpn/easy-rsa/ || exit
EASYRSA_CERT_EXPIRE=3650 ./easyrsa --batch build-client-full "$CLIENT" nopass

# Определение домашней директории
if [ -e "/home/${CLIENT}" ]; then
    homeDir="/home/${CLIENT}"
elif [ "${SUDO_USER}" ]; then
    if [ "${SUDO_USER}" == "root" ]; then
        homeDir="/root"
    else
        homeDir="/home/${SUDO_USER}"
    fi
else
    homeDir="/root"
fi

# Определение типа TLS
TLS_SIG=""
if grep -qs "^tls-crypt" /etc/openvpn/server.conf; then
    TLS_SIG="1"
elif grep -qs "^tls-auth" /etc/openvpn/server.conf; then
    TLS_SIG="2"
fi

# Создание конфигурационного файла
cp /etc/openvpn/client-template.txt "$homeDir/$CLIENT.ovpn"

# Добавляем DNS-настройки в начало файла
{
    echo ""
    echo "# DNS settings"
    echo "dhcp-option DNS 8.8.8.8"
    echo "dhcp-option DNS 8.8.4.4"
    echo ""
} > "$homeDir/$CLIENT.ovpn.tmp"

cat "$homeDir/$CLIENT.ovpn" >> "$homeDir/$CLIENT.ovpn.tmp"
mv "$homeDir/$CLIENT.ovpn.tmp" "$homeDir/$CLIENT.ovpn"

# Добавляем сертификаты и ключи
{
    echo "<ca>"
    cat "/etc/openvpn/easy-rsa/pki/ca.crt"
    echo "</ca>"

    echo "<cert>"
    awk '/BEGIN/,/END CERTIFICATE/' "/etc/openvpn/easy-rsa/pki/issued/$CLIENT.crt"
    echo "</cert>"

    echo "<key>"
    cat "/etc/openvpn/easy-rsa/pki/private/$CLIENT.key"
    echo "</key>"

    case $TLS_SIG in
        1)
            echo "<tls-crypt>"
            cat /etc/openvpn/tls-crypt.key
            echo "</tls-crypt>"
            ;;
        2)
            echo "key-direction 1"
            echo "<tls-auth>"
            cat /etc/openvpn/tls-auth.key
            echo "</tls-auth>"
            ;;
    esac
} >> "$homeDir/$CLIENT.ovpn"

echo "Пользователь $CLIENT успешно добавлен!"
echo "Конфигурационный файл создан: $homeDir/$CLIENT.ovpn"