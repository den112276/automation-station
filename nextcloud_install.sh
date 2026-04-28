#!/bin/bash

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    echo "Этот скрипт должен запускаться с правами root" >&2
    exit 1
fi

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
ORANGE='\033[0;33m'      # Оранжевый
PINK='\033[1;35m'        # Розовый
LIME='\033[1;32m'        # Лаймовый
MAGENTA='\033[1;35m'     # Пурпурный
CYAN='\033[0;36m'        # Голубой
NC='\033[0m' # Без цвета

# Функция определения дистрибутива
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        echo -e "${RED}Не удалось определить дистрибутив Linux${NC}"
        exit 1
    fi
}

# Функция получения списка установленных доменов Nextcloud
get_nextcloud_domains() {
    local domains=()
    # Ищем конфиги Apache
    for conf in /etc/apache2/sites-available/*.conf; do
        if grep -q "DocumentRoot /var/www/" "$conf"; then
            domain=$(grep -oP "ServerName \K[^ ]+" "$conf")
            if [ -n "$domain" ] && [ -d "/var/www/$domain" ]; then
                domains+=("$domain")
            fi
        fi
    done
    echo "${domains[@]}"
}

# Функция проверки существования Nextcloud
check_nextcloud_installed() {
    local domain=$1
    
    # Проверка наличия директории
    if [ -d "/var/www/${domain}" ]; then
        echo -e "${YELLOW}Обнаружена директория Nextcloud: /var/www/${domain}${NC}"
        return 0
    fi
    
    # Проверка конфига Apache
    if [ -f "/etc/apache2/sites-available/${domain}.conf" ]; then
        echo -e "${YELLOW}Обнаружен конфиг Apache: /etc/apache2/sites-available/${domain}.conf${NC}"
        return 0
    fi
    
    # Проверка базы данных (если переданы параметры)
    if [ $# -ge 3 ]; then
        local db_name=$2
        local mysql_root_password=$3
        
        if check_db_exists "$db_name" "$mysql_root_password"; then
            echo -e "${YELLOW}Обнаружена база данных: ${db_name}${NC}"
            return 0
        fi
    fi
    
    return 1
}

# Функция подтверждения действия
confirm_action() {
    local prompt=$1
    local default=${2:-n}
    
    while true; do
        read -p "${prompt} (y/n) [${default}]: " answer
        answer=${answer:-${default}}
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
        
        case "$answer" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo -e "${RED}Ошибка: Введите y/n или yes/no${NC}" ;;
        esac
    done
}

# Функция проверки выполнения команд
check_success() {
    local operation=$1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Успешно: ${operation}${NC}"
        return 0
    else
        echo -e "${RED}Ошибка при выполнении: ${operation}${NC}"
        exit 1
    fi
}

# Функция установки MySQL/MariaDB
install_mysql() {
    echo -e "${CYAN}Установка MySQL/MariaDB...${NC}"
    
    detect_os
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y mariadb-server mariadb-client
            ;;
        centos|rhel|fedora|amzn)
            if [ "$OS" = "amzn" ]; then
                amazon-linux-extras install -y mariadb10.5
            else
                yum install -y mariadb-server mariadb
            fi
            systemctl enable mariadb
            systemctl start mariadb
            ;;
        *)
            echo -e "${RED}Неподдерживаемый дистрибутив Linux${NC}"
            exit 1
            ;;
    esac
    
    check_success "Установка MySQL/MariaDB"
}

# Функция настройки MySQL root пароля
configure_mysql_root() {
    local mysql_root_password=$1
    
    echo -e "${CYAN}Настройка root пароля MySQL...${NC}"
    
    # Пытаемся выполнить настройку сначала с паролем, потом без
    if ! mysql -u root -p"${mysql_root_password}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysql_root_password}';" 2>/dev/null; then
        # Если не получилось с паролем, пробуем без пароля
        mysql --user=root <<_EOF_
ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysql_root_password}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
_EOF_
    fi
    
    check_success "Настройка root пароля MySQL"
}

# Функция проверки подключения к MySQL
check_mysql_connection() {
    local mysql_root_password=$1
    
    # Пытаемся подключиться с паролем
    if mysql -u root -p"${mysql_root_password}" -e ";" 2>/dev/null; then
        echo -e "${GREEN}Успешное подключение к MySQL${NC}"
        return 0
    # Пытаемся подключиться без пароля (если разрешена socket-аутентификация)
    elif mysql -u root -e ";" 2>/dev/null; then
        echo -e "${GREEN}Успешное подключение к MySQL через socket${NC}"
        return 0
    else
        echo -e "${RED}Ошибка подключения к MySQL${NC}"
        return 1
    fi
}

# Функция проверки существования базы данных
check_db_exists() {
    local db_name=$1
    local mysql_root_password=$2
    
    if mysql -u root -p"${mysql_root_password}" -e "USE ${db_name}" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Функция скачивания Nextcloud
download_nextcloud() {
    local mirrors=(
        "https://download.nextcloud.com/server/releases/latest.zip"
        "https://github.com/nextcloud-releases/server/releases/download/v31.0.6/nextcloud-31.0.6.zip"
    )

    echo -e "${CYAN}Доступные зеркала для загрузки:${NC}"
    for i in "${!mirrors[@]}"; do
        echo "$((i+1))) ${mirrors[$i]}"
    done

    while true; do
        read -p "Выберите зеркало для загрузки (1-${#mirrors[@]}): " mirror_choice
        if [[ "$mirror_choice" =~ ^[1-${#mirrors[@]}]$ ]]; then
            selected_mirror=${mirrors[$((mirror_choice-1))]}
            break
        else
            echo -e "${RED}Неверный выбор. Введите число от 1 до ${#mirrors[@]}${NC}"
        fi
    done

    echo -e "${PURPLE}Используется зеркало: $selected_mirror${NC}"

    if [ -f "/tmp/nextcloud.zip" ]; then
        if confirm_action "Найден существующий архив nextcloud.zip. Использовать его?" "y"; then
            echo -e "${CYAN}Используется существующий архив${NC}"
            return 0
        fi
    fi

    echo -e "${CYAN}Загрузка Nextcloud...${NC}"
    if command -v wget &> /dev/null; then
        wget --show-progress -O /tmp/nextcloud.zip "$selected_mirror"
    elif command -v curl &> /dev/null; then
        curl -# -L -o /tmp/nextcloud.zip "$selected_mirror"
    else
        echo -e "${RED}Ошибка: не найдены ни wget, ни curl${NC}"
        exit 1
    fi
    check_success "Загрузка Nextcloud"
}

# Функция установки phpMyAdmin
install_phpmyadmin() {
    echo -e "${PURPLE}=== Установка phpMyAdmin и необходимых PHP модулей ===${NC}"
    
    if dpkg -l | grep -q phpmyadmin; then
        echo -e "${CYAN}phpMyAdmin уже установлен${NC}"
        return 0
    fi

    echo -e "${CYAN}Установка PHP и необходимых модулей...${NC}"
    apt-get install -y php php-cli php-fpm php-json php-common php-mysql php-zip \
    php-gd php-mbstring php-curl php-xml php-pear php-bcmath php-imagick php-intl \
    php-gmp php-bz2 php-tidy php-soap
    check_success "Установка PHP и модулей"

    echo -e "${CYAN}Установка phpMyAdmin...${NC}"
    
    # Установка с автоматической настройкой под Apache
    debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"
    debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean false"
    apt-get install -y phpmyadmin
    check_success "Установка phpMyAdmin"

    # Настройка доступа root
    if confirm_action "Настроить доступ root для phpMyAdmin?" "y"; then
        echo -e "${CYAN}Настройка доступа root...${NC}"
        
        # Получаем пароль root MySQL
        while true; do
            read -sp "Введите текущий пароль root для MySQL (оставьте пустым если нет пароля): " mysql_root_password
            echo
            
            if [ -z "$mysql_root_password" ]; then
                if mysql -u root -e ";" 2>/dev/null; then
                    echo -e "${GREEN}Успешное подключение к MySQL без пароля${NC}"
                    break
                fi
            else
                if mysql -u root -p"${mysql_root_password}" -e ";" 2>/dev/null; then
                    echo -e "${GREEN}Успешное подключение к MySQL с паролем${NC}"
                    break
                fi
            fi
            
            echo -e "${RED}Ошибка подключения к MySQL${NC}"
            if ! confirm_action "Попробовать снова?" "y"; then
                return 1
            fi
        done

        # Настройка конфигурации для разрешения входа под root
        PMA_CONFIG="/etc/phpmyadmin/conf.d/root_login.php"
        cat > "$PMA_CONFIG" <<EOF
<?php
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['AllowRoot'] = true;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;
?>
EOF

        chmod 644 "$PMA_CONFIG"
        chown www-data:www-data "$PMA_CONFIG"

        systemctl restart apache2
        systemctl restart mariadb

        echo -e "${GREEN}phpMyAdmin настроен для входа под root.${NC}"
        echo -e "${PURPLE}URL: http://$(hostname -I | awk '{print $1}')/phpmyadmin${NC}"
    fi
}

# Функция удаления phpMyAdmin
uninstall_phpmyadmin() {
    echo -e "${PURPLE}=== Удаление phpMyAdmin ===${NC}"
    
    if ! dpkg -l | grep -q phpmyadmin; then
        echo -e "${CYAN}phpMyAdmin не установлен${NC}"
        return 0
    fi
    
    if confirm_action "Вы уверены, что хотите удалить phpMyAdmin?" "n"; then
        echo -e "${CYAN}Удаление phpMyAdmin...${NC}"
        
        # Удаление конфигурационного файла root_login.php
        if [ -f "/etc/phpmyadmin/conf.d/root_login.php" ]; then
            rm -f /etc/phpmyadmin/conf.d/root_login.php
        fi
        
        # Удаление phpMyAdmin
        apt-get purge -y phpmyadmin
        apt-get autoremove -y
        rm -rf /etc/phpmyadmin
        check_success "Удаление phpMyAdmin"
        
        echo -e "${GREEN}phpMyAdmin успешно удален${NC}"
    else
        echo -e "${CYAN}Удаление phpMyAdmin отменено${NC}"
    fi
}

# Функция настройки конфигурации Nextcloud
configure_nextcloud() {
    local domain=$1
    local config_file="/var/www/${domain}/config/config.php"
    
    echo -e "${CYAN}Конфигурация Nextcloud будет выполнена после установки через веб-интерфейс${NC}"
    echo -e "${PURPLE}Для настройки работы за обратным прокси выполните следующие шаги:${NC}"
    echo "1. Завершите установку через веб-интерфейс"
    echo "2. Запустите этот скрипт снова и выберите пункт 'Настройка прокси'"
    echo "3. Либо отредактируйте файл ${config_file} вручную, добавив:"
    echo -e "${GREEN}'overwriteprotocol' => 'https',\n'overwrite.cli.url' => 'https://${domain}',\n'overwritehost' => '${domain}',${NC}"
}

# Функция настройки прокси
configure_proxy_settings() {
    echo -e "${PURPLE}=== Настройка параметров прокси ===${NC}"
    
    # Получаем список доменов
    domains=($(get_nextcloud_domains))
    
    if [ ${#domains[@]} -eq 0 ]; then
        echo -e "${RED}Ошибка: Не найдено установленных экземпляров Nextcloud${NC}"
        return 1
    fi
    
    # Выводим меню выбора домена
    echo -e "${BLUE}Выберите домен для настройки:${NC}"
    for i in "${!domains[@]}"; do
        echo "$((i+1))) ${domains[$i]}"
    done
    
    # Запрашиваем выбор пользователя
    while true; do
        read -p "Введите номер домена (1-${#domains[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#domains[@]} ]; then
            domain="${domains[$((choice-1))]}"
            break
        else
            echo -e "${RED}Неверный выбор. Введите число от 1 до ${#domains[@]}${NC}"
        fi
    done

    local config_file="/var/www/${domain}/config/config.php"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Ошибка: Файл конфигурации не найден${NC}"
        echo "Убедитесь, что:"
        echo "1. Nextcloud полностью установлен через веб-интерфейс"
        echo "2. Указано правильное доменное имя"
        return 1
    fi
    
    if grep -q "'overwriteprotocol' => 'https'" "$config_file"; then
        echo -e "${CYAN}Параметры прокси уже настроены${NC}"
        return
    fi
    
    echo -e "${CYAN}Добавление параметров прокси...${NC}"
    sed -i "/);/i \ \ 'overwriteprotocol' => 'https'," "$config_file"
    sed -i "/);/i \ \ 'overwritehost' => '${domain}'," "$config_file"
    
    systemctl reload apache2
    echo -e "${GREEN}Параметры прокси успешно добавлены${NC}"
}

# Функция удаления Nextcloud
uninstall_nextcloud() {
    echo -e "${PURPLE}=== Удаление Nextcloud ===${NC}"
    
    # Получаем список доменов
    domains=($(get_nextcloud_domains))
    
    if [ ${#domains[@]} -eq 0 ]; then
        echo -e "${RED}Ошибка: Не найдено установленных экземпляров Nextcloud${NC}"
        return 1
    fi
    
    # Выводим меню выбора домена
    echo -e "${BLUE}Выберите домен для удаления:${NC}"
    for i in "${!domains[@]}"; do
        echo "$((i+1))) ${domains[$i]}"
    done
    
    # Запрашиваем выбор пользователя
    while true; do
        read -p "Введите номер домена (1-${#domains[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#domains[@]} ]; then
            domain="${domains[$((choice-1))]}"
            break
        else
            echo -e "${RED}Неверный выбор. Введите число от 1 до ${#domains[@]}${NC}"
        fi
    done

    if ! confirm_action "Вы уверены, что хотите удалить Nextcloud для домена ${domain}?" "n"; then
        return
    fi

    # Проверка существования конфигурации Apache
    if [ -f "/etc/apache2/sites-available/${domain}.conf" ]; then
        echo -e "${CYAN}Удаление конфигурации Apache...${NC}"
        a2dissite "${domain}.conf"
        rm -f "/etc/apache2/sites-available/${domain}.conf"
        systemctl restart apache2
        check_success "Удаление конфигурации Apache"
    else
        echo -e "${CYAN}Файл конфигурации Apache не найден${NC}"
    fi
    
    # Проверка существования директории Nextcloud
    if [ -d "/var/www/${domain}" ]; then
        echo -e "${CYAN}Удаление файлов Nextcloud...${NC}"
        rm -rf "/var/www/${domain}"
        if [ -d "/var/www/${domain}" ]; then
            echo -e "${RED}Ошибка: Файлы не удалены${NC}"
            return 1
        else
            echo -e "${GREEN}Файлы успешно удалены${NC}"
        fi
    else
        echo -e "${CYAN}Директория /var/www/${domain} не существует${NC}"
    fi
    
    # Удаление базы данных
    if confirm_action "Удалить базу данных и пользователя Nextcloud?" "n"; then
        read -p "Введите имя базы данных Nextcloud (по умолчанию nextcloud): " db_name
        db_name=${db_name:-nextcloud}
        
        read -p "Введите имя пользователя базы данных (по умолчанию nextcloud_user): " db_user
        db_user=${db_user:-nextcloud_user}
        
        attempts=0
        max_attempts=3
        mysql_connected=0

        while [ $attempts -lt $max_attempts ]; do
            read -sp "Введите пароль root для MySQL: " mysql_root_password
            echo

            if [ -z "$mysql_root_password" ]; then
                echo -e "${RED}Ошибка: пароль не может быть пустым${NC}"
                attempts=$((attempts+1))
                continue
            fi

            if check_mysql_connection "${mysql_root_password}"; then
                mysql_connected=1
                break
            else
                attempts=$((attempts+1))
                remaining_attempts=$((max_attempts - attempts))
                echo -e "${RED}Ошибка подключения. Осталось попыток: ${remaining_attempts}${NC}"
            fi
        done

        if [ $mysql_connected -eq 0 ]; then
            echo -e "${RED}Превышено количество попыток. Удаление базы данных и пользователя отменено.${NC}"
            return 1
        fi

        # Проверка и удаление базы данных
        if mysql -u root -p"${mysql_root_password}" -e "USE ${db_name}" 2>/dev/null; then
            echo -e "${CYAN}Удаление базы данных ${db_name}...${NC}"
            if mysql -u root -p"${mysql_root_password}" -e "DROP DATABASE IF EXISTS ${db_name}"; then
                echo -e "${GREEN}База данных ${db_name} успешно удалена${NC}"
                
                # Проверка и удаление пользователя MySQL только если база была удалена
                echo -e "${CYAN}Проверка существования пользователя MySQL...${NC}"
                user_exists=$(mysql -u root -p"${mysql_root_password}" -sN -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '${db_user}')" 2>/dev/null)
                
                if [ $? -eq 0 ]; then
                    if [ "$user_exists" -eq 1 ]; then
                        echo -e "${CYAN}Удаление пользователя MySQL...${NC}"
                        if mysql -u root -p"${mysql_root_password}" -e "DROP USER IF EXISTS '${db_user}'@'localhost'"; then
                            echo -e "${GREEN}Пользователь MySQL успешно удален${NC}"
                        else
                            echo -e "${RED}Ошибка при удалении пользователя MySQL${NC}"
                        fi
                    else
                        echo -e "${CYAN}Пользователь MySQL ${db_user} не существует${NC}"
                    fi
                else
                    echo -e "${RED}Ошибка при проверке пользователя MySQL${NC}"
                fi
            else
                echo -e "${RED}Ошибка при удалении базы данных${NC}"
            fi
        else
            echo -e "${CYAN}База данных ${db_name} не существует${NC}"
            return
        fi
    fi
    
    # Удаление cron-заданий
    echo -e "${CYAN}Проверка задач cron...${NC}"
    if crontab -u www-data -l 2>/dev/null | grep -q "/var/www/${domain}/cron.php"; then
        echo -e "${CYAN}Удаление задач cron...${NC}"
        crontab -u www-data -l | grep -v "/var/www/${domain}/cron.php" | crontab -u www-data -
        check_success "Удаление задач cron"
    else
        echo -e "${CYAN}Задачи cron не найдены${NC}"
    fi
    
    # Удаление SSL сертификата
    if [ -d "/etc/letsencrypt/live/${domain}" ]; then
        if confirm_action "Удалить Let's Encrypt сертификат для ${domain}?" "n"; then
            echo -e "${CYAN}Удаление SSL сертификата...${NC}"
            certbot delete --cert-name "${domain}" --non-interactive
            check_success "Удаление SSL сертификата"
        fi
    else
        echo -e "${CYAN}SSL сертификат не найден${NC}"
    fi
        # Удаление Apache2 (по желанию)
    if confirm_action "Удалить Apache2 и все связанные с ним пакеты?" "n"; then
        echo -e "${CYAN}Удаление Apache2...${NC}"
        apt-get purge -y apache2 apache2-utils apache2-bin apache2.2-common
        apt-get autoremove -y
        check_success "Удаление Apache2"
    else
        echo -e "${CYAN}Удаление Apache2 отменено${NC}"
    fi

    echo -e "${GREEN}=== Nextcloud и все связанные компоненты успешно удалены ===${NC}"
}

# Функция установки Nextcloud
install_nextcloud() {
    echo -e "${PURPLE}=== Установка Nextcloud ===${NC}"

    # Ввод параметров
    while true; do
        read -p "Введите доменное имя для Nextcloud (например, cloud.example.com): " domain
        if [ -z "$domain" ]; then
            echo -e "${RED}Ошибка: Доменное имя не может быть пустым${NC}"
        else
            break
        fi
    done

    # Проверка существующей установки
    if check_nextcloud_installed "$domain"; then
        echo -e "${YELLOW}Внимание: Обнаружены следы существующей установки Nextcloud для домена ${domain}${NC}"
        
        if ! confirm_action "Продолжить установку? (Это может перезаписать существующую установку)" "n"; then
            return 1
        fi
    fi

    read -p "Введите имя базы данных (по умолчанию nextcloud): " db_name
    db_name=${db_name:-nextcloud}
    
    read -p "Введите пользователя базы данных (по умолчанию nextcloud_user): " db_user
    db_user=${db_user:-nextcloud_user}
    
    while true; do
        read -sp "Введите пароль пользователя БД: " db_password
        echo
        if [ -z "$db_password" ]; then
            echo -e "${RED}Ошибка: Пароль не может быть пустым${NC}"
        else
            break
        fi
    done

    # Обновление системы
    echo -e "${CYAN}Обновление системы...${NC}"
    apt-get update && apt-get upgrade -y
    check_success "Обновление системы"

    # Установка зависимостей
    echo -e "${CYAN}Установка необходимых пакетов...${NC}"
    apt-get install -y apache2 libapache2-mod-php php-gd php-mysql \
    php-curl php-mbstring php-intl php-gmp php-bcmath php-xml php-imagick php-zip \
    unzip wget curl
    check_success "Установка пакетов"

    # Установка и настройка MySQL
    install_mysql
    
    # Настройка MySQL root пароля
    while true; do
        read -sp "Введите пароль root для MySQL: " mysql_root_password
        echo
        
        if [ -z "$mysql_root_password" ]; then
            echo -e "${RED}Ошибка: Пароль не может быть пустым${NC}"
            continue
        fi
        
        configure_mysql_root "$mysql_root_password"
        
        if check_mysql_connection "$mysql_root_password"; then
            break
        else
            if ! confirm_action "Попробовать снова?" "y"; then
                return 1
            fi
        fi
    done

    # Создание базы данных и пользователя
    mysql -u root -p"${mysql_root_password}" -e "CREATE DATABASE IF NOT EXISTS ${db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    mysql -u root -p"${mysql_root_password}" -e "CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_password}';"
    mysql -u root -p"${mysql_root_password}" -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';"
    mysql -u root -p"${mysql_root_password}" -e "FLUSH PRIVILEGES;"
    check_success "Настройка базы данных"

    # Загрузка Nextcloud
    download_nextcloud
    
    echo -e "${CYAN}Распаковка Nextcloud...${NC}"
    unzip -q /tmp/nextcloud.zip -d /var/www/
    mv /var/www/nextcloud "/var/www/${domain}"
    chown -R www-data:www-data "/var/www/${domain}"
    check_success "Распаковка Nextcloud"

    # Настройка Apache
    echo -e "${CYAN}Настройка веб-сервера...${NC}"
    cat > "/etc/apache2/sites-available/${domain}.conf" <<EOF
<VirtualHost *:80>
    ServerName ${domain}
    DocumentRoot /var/www/${domain}
    
    # Более надежное перенаправление на страницу логина
    RewriteEngine On
    RewriteRule ^/$ /index.php/login [R=302,L]
    
    <Directory /var/www/${domain}>
        Options FollowSymlinks
        AllowOverride All
        Require all granted
        
        <IfModule mod_rewrite.c>
            RewriteEngine on
            RewriteRule .* - [env=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
        </IfModule>
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog ${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

    a2ensite "${domain}.conf"
    a2enmod rewrite headers env dir mime
    
    if [ -f "/etc/apache2/sites-available/000-default.conf" ]; then
        a2dissite 000-default.conf
    fi
    
    systemctl restart apache2
    check_success "Настройка Apache"

    # Установка SSL
    if confirm_action "Установить Let's Encrypt SSL сертификат?" "y"; then
        echo -e "${CYAN}Установка SSL сертификата...${NC}"
        apt-get install -y certbot python3-certbot-apache
        
        # Запрос email для Let's Encrypt
        while true; do
            read -p "Введите email для уведомлений Let's Encrypt: " le_email
            if [[ "$le_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
                break
            else
                echo -e "${RED}Ошибка: Введите корректный email адрес${NC}"
            fi
        done
        
        certbot --apache -d "${domain}" --non-interactive --agree-tos --email "${le_email}" --redirect
        check_success "Установка SSL сертификата"
        
        # Автообновление сертификата
        (crontab -l 2>/dev/null; echo "0 5 * * * /usr/bin/certbot renew --quiet --post-hook \"systemctl reload apache2\"") | crontab -
        echo -e "${GREEN}SSL сертификат успешно установлен${NC}"
    fi

    # Настройка cron
    echo -e "${CYAN}Настройка фоновых задач...${NC}"
    (crontab -u www-data -l 2>/dev/null; echo "*/5 * * * * php -f /var/www/${domain}/cron.php") | crontab -u www-data -
    check_success "Настройка cron"

    # Настройка конфигурации Nextcloud
    configure_nextcloud "$domain"

    # Очистка
    echo -e "${CYAN}Очистка временных файлов...${NC}"
    rm -f /tmp/nextcloud.zip
    check_success "Очистка временных файлов"

    # Завершение
    echo -e "${GREEN}=== Установка Nextcloud завершена успешно! ===${NC}"
    echo -e "Доступ к Nextcloud: https://${domain}"
    echo -e "Завершите настройку через веб-интерфейс"
}

# Главное меню
show_menu() {
    clear
    echo -e "${PURPLE}=== Управление Nextcloud ===${NC}"
    echo -e "1) ${GREEN}Установить Nextcloud${NC}"         # Зеленый
    echo -e "2) ${RED}Удалить Nextcloud${NC}"             # Красный
    echo -e "3) ${YELLOW}Настроить параметры прокси${NC}" # Желтый
    echo -e "4) ${PINK}Установить phpMyAdmin${NC}"        # Розовый
    echo -e "5) ${ORANGE}Удалить phpMyAdmin${NC}"         # Оранжевый
    echo -e "6) ${LIME}Выход${NC}"                       # Лаймовый
    echo -n -e "${MAGENTA}Выберите действие (1-6): ${NC}" # Пурпурный
}

# Проверка существующих установок Nextcloud при запуске
existing_installs=$(get_nextcloud_domains)
if [ -n "$existing_installs" ]; then
    echo -e "${YELLOW}Обнаружены существующие установки Nextcloud:${NC}"
    for domain in $existing_installs; do
        echo -e " - ${domain}"
    done
    echo
fi

while true; do
    show_menu
    read action
    case $action in
        1)
            install_nextcloud
            read -p "Нажмите Enter для продолжения..."
            ;;
        2)
            uninstall_nextcloud
            read -p "Нажмите Enter для продолжения..."
            ;;
        3)
            configure_proxy_settings
            read -p "Нажмите Enter для продолжения..."
            ;;
        4)
            install_phpmyadmin
            read -p "Нажмите Enter для продолжения..."
            ;;
        5)
            uninstall_phpmyadmin
            read -p "Нажмите Enter для продолжения..."
            ;;
        6)
            echo -e "${GREEN}Выход...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор. Попробуйте снова.${NC}"
            read -p "Нажмите Enter для продолжения..."
            ;;
    esac
done