#!/bin/bash

# Интерактивный менеджер конфигов nginx с поддержкой Let's Encrypt
# Author: System Admin
# Version: 3.4 - Поддержка Let's Encrypt

# Конфигурация
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
BACKUP_DIR="/tmp/nginx_backups"
LOG_FILE="/var/log/nginx_config_manager.log"
SSL_DIR="/etc/letsencrypt/live"  # Изменено на стандартный путь Let's Encrypt
WWW_ROOT="/var/www"
LETSENCRYPT_WEBROOT="/var/www/html"  # Webroot для получения сертификатов

# Цвета для интерфейса
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# Функция очистки экрана
clear_screen() {
    clear
}

# Функция паузы и очистки
pause_and_clear() {
    echo ""
    echo -n "Нажмите Enter для продолжения..."
    read
    clear_screen
}

# Функция отображения заголовка
show_header() {
    echo -e "${CYAN}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║         NGINX CONFIG MANAGER - Поддержка Let's Encrypt        ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE" > /dev/null 2>&1
}

# Функция проверки прав root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}❌ Ошибка: Скрипт требует прав root${NC}"
        echo -e "${YELLOW}Запустите с sudo: sudo $0${NC}"
        exit 1
    fi
}

# Функция проверки установки certbot
check_certbot() {
    if ! command -v certbot &> /dev/null; then
        echo -e "${YELLOW}⚠️  Certbot не установлен${NC}"
        read -p "Установить certbot? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Установка certbot...${NC}"
            sudo apt-get update -qq
            sudo apt-get install -y certbot python3-certbot-nginx
            echo -e "${GREEN}✅ Certbot установлен${NC}"
        else
            return 1
        fi
    fi
    return 0
}

# Функция создания бэкапа
create_backup() {
    local config_name="$1"
    local backup_path="$BACKUP_DIR/${config_name}.$(date +%Y%m%d_%H%M%S).bak"
    
    sudo mkdir -p "$BACKUP_DIR" 2>/dev/null
    if [ -f "$NGINX_CONF_DIR/$config_name" ]; then
        sudo cp "$NGINX_CONF_DIR/$config_name" "$backup_path" 2>/dev/null
        echo -e "${GREEN}✅ Бэкап создан: $backup_path${NC}"
        log "Создан бэкап конфига: $config_name"
    fi
}

# Функция тестирования конфигурации
test_configuration() {
    echo -e "\n${BLUE}🔍 Проверка синтаксиса nginx...${NC}"
    if sudo nginx -t 2>&1; then
        echo -e "${GREEN}✅ Синтаксис корректный${NC}"
        return 0
    else
        echo -e "${RED}❌ Ошибка в синтаксисе${NC}"
        return 1
    fi
}

# Функция перезагрузки nginx
reload_nginx() {
    echo -e "\n${BLUE}🔄 Перезагрузка nginx...${NC}"
    if sudo systemctl reload nginx 2>/dev/null; then
        echo -e "${GREEN}✅ Nginx успешно перезагружен${NC}"
        log "Nginx перезагружен"
        return 0
    else
        echo -e "${RED}❌ Ошибка перезагрузки nginx${NC}"
        return 1
    fi
}

# Функция получения Let's Encrypt сертификата
obtain_letsencrypt_cert() {
    local domain="$1"
    local email="$2"
    
    echo -e "${BLUE}🔐 Получение Let's Encrypt сертификата для $domain...${NC}"
    
    # Создаем временный HTTP конфиг для получения сертификата
    local temp_config="$NGINX_CONF_DIR/${domain}.temp.conf"
    sudo tee "$temp_config" > /dev/null << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    
    root $LETSENCRYPT_WEBROOT;
    
    location /.well-known/acme-challenge/ {
        root $LETSENCRYPT_WEBROOT;
    }
    
    location / {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF
    
    # Активируем временный конфиг
    sudo ln -sf "$temp_config" "$NGINX_ENABLED_DIR/${domain}.temp.conf"
    sudo systemctl reload nginx
    
    # Получаем сертификат
    local certbot_cmd="certbot certonly --webroot -w $LETSENCRYPT_WEBROOT -d $domain -d www.$domain --non-interactive --agree-tos"
    if [ -n "$email" ]; then
        certbot_cmd="$certbot_cmd --email $email"
    else
        certbot_cmd="$certbot_cmd --register-unsafely-without-email"
    fi
    
    if sudo $certbot_cmd; then
        echo -e "${GREEN}✅ SSL сертификат успешно получен!${NC}"
        log "Получен Let's Encrypt сертификат для $domain"
        
        # Удаляем временный конфиг
        sudo rm -f "$temp_config"
        sudo rm -f "$NGINX_ENABLED_DIR/${domain}.temp.conf"
        sudo systemctl reload nginx
        
        return 0
    else
        echo -e "${RED}❌ Ошибка получения сертификата${NC}"
        # Удаляем временный конфиг
        sudo rm -f "$temp_config"
        sudo rm -f "$NGINX_ENABLED_DIR/${domain}.temp.conf"
        sudo systemctl reload nginx
        return 1
    fi
}

# Функция обновления сертификата
renew_certificate() {
    local domain="$1"
    
    echo -e "${BLUE}🔄 Обновление сертификата для $domain...${NC}"
    
    if sudo certbot renew --cert-name "$domain" --webroot -w "$LETSENCRYPT_WEBROOT"; then
        echo -e "${GREEN}✅ Сертификат обновлен${NC}"
        log "Обновлен сертификат для $domain"
        sudo systemctl reload nginx
        return 0
    else
        echo -e "${RED}❌ Ошибка обновления сертификата${NC}"
        return 1
    fi
}

# Функция активации конфига
activate_config() {
    local config_name="$1"
    local config_path="$NGINX_CONF_DIR/$config_name"
    local enabled_path="$NGINX_ENABLED_DIR/$config_name"
    
    clear_screen
    show_header
    
    echo -e "${BLUE}🔧 АКТИВАЦИЯ КОНФИГА${NC}\n"
    
    if [ ! -f "$config_path" ]; then
        echo -e "${RED}❌ Конфиг '$config_name' не найден${NC}"
        pause_and_clear
        return 1
    fi
    
    if [ -L "$enabled_path" ]; then
        echo -e "${YELLOW}⚠️  Конфиг '$config_name' уже активирован${NC}"
        read -p "Хотите переактивировать? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            pause_and_clear
            return 0
        fi
        sudo rm "$enabled_path"
    fi
    
    create_backup "$config_name"
    
    echo -e "${BLUE}🔗 Активация конфига...${NC}"
    sudo ln -s "$config_path" "$enabled_path" 2>/dev/null
    
    if test_configuration && reload_nginx; then
        echo -e "\n${GREEN}✅ Конфиг '$config_name' успешно активирован!${NC}"
        log "Активирован конфиг: $config_name"
    else
        sudo rm -f "$enabled_path" 2>/dev/null
        echo -e "\n${RED}❌ Активация отменена из-за ошибок${NC}"
        log "Ошибка активации конфига: $config_name"
    fi
    
    pause_and_clear
}

# Функция деактивации конфига
deactivate_config() {
    local config_name="$1"
    local enabled_path="$NGINX_ENABLED_DIR/$config_name"
    
    clear_screen
    show_header
    
    echo -e "${BLUE}🔧 ДЕАКТИВАЦИЯ КОНФИГА${NC}\n"
    
    if [ ! -L "$enabled_path" ]; then
        echo -e "${YELLOW}⚠️  Конфиг '$config_name' не активирован${NC}"
        pause_and_clear
        return 0
    fi
    
    echo -e "${BLUE}🔗 Деактивация конфига...${NC}"
    sudo rm "$enabled_path" 2>/dev/null
    
    if test_configuration && reload_nginx; then
        echo -e "\n${GREEN}✅ Конфиг '$config_name' деактивирован!${NC}"
        log "Деактивирован конфиг: $config_name"
    else
        echo -e "\n${RED}❌ Ошибка при деактивации${NC}"
    fi
    
    pause_and_clear
}

# Функция создания директории сайта
create_site_directory() {
    local site_name="$1"
    local site_path="$WWW_ROOT/$site_name"
    
    if [ ! -d "$site_path" ]; then
        echo -e "${BLUE}📁 Создание директории сайта: $site_path${NC}"
        sudo mkdir -p "$site_path"
        
        sudo tee "$site_path/index.html" > /dev/null << EOF
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$site_name</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            text-align: center;
            padding: 2rem;
            background: rgba(255,255,255,0.1);
            border-radius: 10px;
        }
        h1 { font-size: 2rem; margin-bottom: 1rem; }
        p { font-size: 1.2rem; opacity: 0.9; }
        .config-name { font-size: 1rem; margin-top: 1rem; opacity: 0.7; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 $site_name</h1>
        <p>Сайт успешно настроен на Nginx</p>
        <p>Время создания: $(date '+%Y-%m-%d %H:%M:%S')</p>
        <div class="config-name">Конфиг: $site_name</div>
    </div>
</body>
</html>
EOF
        sudo chown -R www-data:www-data "$site_path"
        echo -e "${GREEN}✅ Директория сайта создана с тестовой страницей${NC}"
    else
        echo -e "${YELLOW}⚠️  Директория сайта уже существует${NC}"
    fi
}

# Функции генерации конфигов
generate_http_config() {
    local domain="$1"
    cat << EOF
# Конфигурация для домена $domain (HTTP)
# Создано: $(date)

server {
    listen 80;
    listen [::]:80;
    
    server_name $domain www.$domain;
    
    root $WWW_ROOT/$domain;
    index index.html index.htm index.php;
    
    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Для Let's Encrypt
    location ~ /.well-known/acme-challenge {
        root $LETSENCRYPT_WEBROOT;
        allow all;
    }
    
    location ~ /\. {
        deny all;
    }
}
EOF
}

generate_https_config() {
    local domain="$1"
    cat << EOF
# Конфигурация для домена $domain (HTTPS с Let's Encrypt)
# Создано: $(date)

# HTTP редирект на HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    
    # Для Let's Encrypt
    location ~ /.well-known/acme-challenge {
        root $LETSENCRYPT_WEBROOT;
        allow all;
    }
    
    return 301 https://\$server_name\$request_uri;
}

# HTTPS основная конфигурация
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    server_name $domain www.$domain;
    
    root $WWW_ROOT/$domain;
    index index.html index.htm index.php;
    
    # SSL сертификаты Let's Encrypt
    ssl_certificate $SSL_DIR/$domain/fullchain.pem;
    ssl_certificate_key $SSL_DIR/$domain/privkey.pem;
    
    # SSL настройки
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # HSTS (раскомментировать после проверки)
    # add_header Strict-Transport-Security "max-age=63072000" always;
    
    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ /\. {
        deny all;
    }
    
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    
    gzip on;
    gzip_vary on;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
EOF
}

generate_wordpress_https_config() {
    local domain="$1"
    cat << EOF
# WordPress конфигурация для $domain (HTTPS с Let's Encrypt)
# Создано: $(date)

# HTTP редирект на HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    
    location ~ /.well-known/acme-challenge {
        root $LETSENCRYPT_WEBROOT;
        allow all;
    }
    
    return 301 https://\$server_name\$request_uri;
}

# HTTPS основная конфигурация
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    server_name $domain www.$domain;
    
    root $WWW_ROOT/$domain;
    index index.php index.html index.htm;
    
    # SSL сертификаты Let's Encrypt
    ssl_certificate $SSL_DIR/$domain/fullchain.pem;
    ssl_certificate_key $SSL_DIR/$domain/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    
    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    location = /wp-config.php {
        deny all;
    }
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires max;
        log_not_found off;
    }
}
EOF
}

generate_proxy_config() {
    local domain="$1"
    local proxy_pass="$2"
    cat << EOF
# Reverse proxy конфигурация для $domain
# Создано: $(date)

server {
    listen 80;
    listen [::]:80;
    
    server_name $domain www.$domain;
    
    location ~ /.well-known/acme-challenge {
        root $LETSENCRYPT_WEBROOT;
        allow all;
    }
    
    location / {
        proxy_pass $proxy_pass;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
}

generate_proxy_https_config() {
    local domain="$1"
    local proxy_pass="$2"
    cat << EOF
# Reverse proxy конфигурация для $domain (HTTPS)
# Создано: $(date)

# HTTP редирект на HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    
    location ~ /.well-known/acme-challenge {
        root $LETSENCRYPT_WEBROOT;
        allow all;
    }
    
    return 301 https://\$server_name\$request_uri;
}

# HTTPS прокси
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    server_name $domain www.$domain;
    
    ssl_certificate $SSL_DIR/$domain/fullchain.pem;
    ssl_certificate_key $SSL_DIR/$domain/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    
    location / {
        proxy_pass $proxy_pass;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
}

# Функция создания конфига
create_any_config() {
    clear_screen
    show_header
    
    echo -e "${BLUE}📝 СОЗДАНИЕ НОВОГО КОНФИГА${NC}\n"
    echo -e "${YELLOW}Введите доменное имя (например: example.com):${NC}"
    read -p "> " domain
    
    if [ -z "$domain" ]; then
        echo -e "${RED}❌ Домен не может быть пустым${NC}"
        pause_and_clear
        return 1
    fi
    
    local config_name="${domain}.conf"
    local config_path="$NGINX_CONF_DIR/$config_name"
    
    if [ -f "$config_path" ]; then
        echo -e "${RED}❌ Конфиг для домена $domain уже существует${NC}"
        pause_and_clear
        return 1
    fi
    
    echo -e "\n${BLUE}Выберите тип конфигурации:${NC}"
    echo "1) HTTP сайт (порт 80)"
    echo "2) HTTPS сайт (с Let's Encrypt)"
    echo "3) WordPress + HTTPS (с Let's Encrypt)"
    echo "4) Reverse proxy HTTP"
    echo "5) Reverse proxy HTTPS (с Let's Encrypt)"
    read -p "Выберите [1-5]: " type_choice
    
    # Создаем директорию сайта для WordPress или обычного сайта
    if [[ "$type_choice" == "1" || "$type_choice" == "2" || "$type_choice" == "3" ]]; then
        create_site_directory "$domain"
    fi
    
    local config_content=""
    local need_ssl=false
    
    case $type_choice in
        1)
            config_content=$(generate_http_config "$domain")
            ;;
        2)
            need_ssl=true
            config_content=$(generate_https_config "$domain")
            ;;
        3)
            need_ssl=true
            config_content=$(generate_wordpress_https_config "$domain")
            ;;
        4)
            echo -e "${BLUE}Введите адрес прокси (например: http://localhost:3000):${NC}"
            read -p "> " proxy_pass
            config_content=$(generate_proxy_config "$domain" "$proxy_pass")
            ;;
        5)
            need_ssl=true
            echo -e "${BLUE}Введите адрес прокси (например: http://localhost:3000):${NC}"
            read -p "> " proxy_pass
            config_content=$(generate_proxy_https_config "$domain" "$proxy_pass")
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор${NC}"
            pause_and_clear
            return 1
            ;;
    esac
    
    # Сохраняем конфиг
    echo "$config_content" | sudo tee "$config_path" > /dev/null
    sudo chmod 644 "$config_path"
    
    echo -e "\n${GREEN}✅ Конфиг создан: $config_path${NC}"
    
    # Если нужен SSL, получаем сертификат Let's Encrypt
    if [ "$need_ssl" = true ]; then
        echo -e "\n${BLUE}🔐 Настройка SSL для $domain${NC}"
        
        if check_certbot; then
            echo -e "${YELLOW}Введите email для Let's Encrypt (опционально):${NC}"
            read -p "> " email
            
            # Сначала активируем HTTP конфиг для получения сертификата
            echo -e "${BLUE}Активация временной HTTP конфигурации...${NC}"
            sudo ln -sf "$config_path" "$NGINX_ENABLED_DIR/$config_name"
            sudo systemctl reload nginx
            
            if obtain_letsencrypt_cert "$domain" "$email"; then
                echo -e "${GREEN}✅ SSL сертификат успешно установлен!${NC}"
            else
                echo -e "${RED}❌ Не удалось получить SSL сертификат${NC}"
                read -p "Продолжить без HTTPS? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    sudo rm -f "$config_path"
                    sudo rm -f "$NGINX_ENABLED_DIR/$config_name"
                    pause_and_clear
                    return 1
                fi
            fi
        fi
    fi
    
    # Вопрос про редактирование
    echo -e "\n${BLUE}Открыть для редактирования? (y/N):${NC}"
    read -n 1 edit_choice
    echo
    if [[ $edit_choice =~ ^[Yy]$ ]]; then
        ${EDITOR:-nano} "$config_path"
        echo -e "\n${GREEN}✅ Редактирование завершено${NC}"
    fi
    
    # Вопрос про активацию
    echo -e "\n${BLUE}Активировать конфиг сейчас? (y/N):${NC}"
    read activate_choice
    echo
    
    if [[ $activate_choice =~ ^[Yy]$ ]]; then
        clear_screen
        show_header
        echo -e "${BLUE}Активация конфига...${NC}\n"
        
        local enabled_path="$NGINX_ENABLED_DIR/$config_name"
        
        if [ -L "$enabled_path" ]; then
            echo -e "${YELLOW}⚠️  Конфиг уже активирован${NC}"
        else
            sudo ln -s "$config_path" "$enabled_path" 2>/dev/null
            
            if test_configuration && reload_nginx; then
                echo -e "\n${GREEN}✅ Конфиг '$config_name' успешно активирован!${NC}"
                log "Создан и активирован конфиг: $config_name"
            else
                sudo rm -f "$enabled_path" 2>/dev/null
                echo -e "\n${RED}❌ Активация отменена из-за ошибок${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}ℹ️  Конфиг создан, но не активирован${NC}"
        log "Создан но не активирован конфиг: $config_name"
    fi
    
    pause_and_clear
}

# Функция обновления всех сертификатов
renew_all_certificates() {
    clear_screen
    show_header
    
    echo -e "${BLUE}🔄 ОБНОВЛЕНИЕ ВСЕХ LET'S ENCRYPT СЕРТИФИКАТОВ${NC}\n"
    
    if ! check_certbot; then
        pause_and_clear
        return 1
    fi
    
    echo -e "${BLUE}Запуск certbot renew...${NC}"
    if sudo certbot renew --webroot -w "$LETSENCRYPT_WEBROOT" --quiet; then
        echo -e "${GREEN}✅ Все сертификаты успешно обновлены${NC}"
        log "Обновлены все Let's Encrypt сертификаты"
        sudo systemctl reload nginx
    else
        echo -e "${RED}❌ Ошибка при обновлении сертификатов${NC}"
    fi
    
    pause_and_clear
}

# Функция показа статуса
show_status() {
    clear_screen
    show_header
    
    echo -e "${BLUE}📊 СТАТУС КОНФИГОВ NGINX${NC}\n"
    
    local available_count=0
    local enabled_count=0
    
    echo -e "${YELLOW}📁 Все конфиги в sites-available:${NC}\n"
    
    local configs=()
    if [ -d "$NGINX_CONF_DIR" ]; then
        while IFS= read -r conf; do
            if [ -f "$conf" ]; then
                configs+=("$(basename "$conf")")
            fi
        done < <(find "$NGINX_CONF_DIR" -maxdepth 1 -type f 2>/dev/null | sort)
    fi
    
    if [ ${#configs[@]} -eq 0 ]; then
        echo -e "  ${RED}○ Нет конфигов в $NGINX_CONF_DIR${NC}"
    else
        for config_file in "${configs[@]}"; do
            available_count=$((available_count + 1))
            
            if [ -L "$NGINX_ENABLED_DIR/$config_file" ]; then
                echo -e "  ${GREEN}✅ $config_file${NC} ${CYAN}→ АКТИВЕН${NC}"
                enabled_count=$((enabled_count + 1))
            else
                echo -e "  ${RED}❌ $config_file${NC} ${YELLOW}→ НЕАКТИВЕН${NC}"
            fi
            
            local config_path="$NGINX_CONF_DIR/$config_file"
            if [ -f "$config_path" ]; then
                local server_name=$(grep -m 1 "server_name" "$config_path" 2>/dev/null | grep -v "#" | awk '{print $2}' | sed 's/;//')
                if [ -n "$server_name" ] && [ "$server_name" != "_" ]; then
                    echo -e "     ${BLUE}🎯 Server: $server_name${NC}"
                fi
                
                if grep -q "ssl_certificate.*letsencrypt" "$config_path" 2>/dev/null; then
                    echo -e "     ${GREEN}🔒 Let's Encrypt HTTPS${NC}"
                elif grep -q "ssl_certificate" "$config_path" 2>/dev/null; then
                    echo -e "     ${GREEN}🔒 HTTPS (Custom)${NC}"
                elif grep -q "proxy_pass" "$config_path" 2>/dev/null; then
                    local proxy_target=$(grep -m 1 "proxy_pass" "$config_path" | awk '{print $2}' | sed 's/;//')
                    echo -e "     ${MAGENTA}🔄 Proxy -> $proxy_target${NC}"
                elif grep -q "fastcgi_pass" "$config_path" 2>/dev/null; then
                    echo -e "     ${MAGENTA}📝 PHP${NC}"
                else
                    echo -e "     ${GREEN}🌐 HTTP${NC}"
                fi
            fi
            echo ""
        done
    fi
    
    echo -e "${BLUE}📊 Статистика:${NC}"
    echo -e "  Всего конфигов: ${CYAN}${available_count}${NC}"
    echo -e "  Активных: ${GREEN}${enabled_count}${NC}"
    echo -e "  Неактивных: ${RED}$((available_count - enabled_count))${NC}"
    
    echo -e "\n${BLUE}🔗 Активные ссылки в sites-enabled:${NC}\n"
    local has_links=false
    if [ -d "$NGINX_ENABLED_DIR" ]; then
        for link in "$NGINX_ENABLED_DIR"/*; do
            if [ -L "$link" ]; then
                has_links=true
                local target=$(readlink "$link" 2>/dev/null)
                echo -e "  ${GREEN}→ $(basename "$link")${NC} ${CYAN}->${NC} $target"
            fi
        done
    fi
    
    if [ "$has_links" = false ]; then
        echo -e "  ${YELLOW}○ Нет активных ссылок${NC}"
    fi
    
    pause_and_clear
}

# Функция отображения меню
show_menu() {
    echo -e "${CYAN}${BOLD}ДОСТУПНЫЕ ДЕЙСТВИЯ:${NC}\n"
    echo -e "  ${GREEN}1)${NC} Активировать конфиг"
    echo -e "  ${RED}2)${NC} Деактивировать конфиг"
    echo -e "  ${BLUE}3)${NC} Показать статус всех конфигов"
    echo -e "  ${MAGENTA}4)${NC} Создать новый конфиг (с Let's Encrypt)"
    echo -e "  ${YELLOW}5)${NC} Редактировать конфиг"
    echo -e "  ${CYAN}6)${NC} Просмотреть конфиг"
    echo -e "  ${RED}7)${NC} Удалить конфиг"
    echo -e "  ${BLUE}8)${NC} Проверить синтаксис"
    echo -e "  ${BLUE}9)${NC} Перезагрузить nginx"
    echo -e "  ${MAGENTA}R)${NC} Обновить все Let's Encrypt сертификаты"
    echo -e "  ${WHITE}0)${NC} Выход"
    echo ""
}

# Функция выбора конфига
select_config() {
    local action="$1"
    local configs=()
    
    if [ -d "$NGINX_CONF_DIR" ]; then
        while IFS= read -r conf; do
            if [ -f "$conf" ]; then
                configs+=("$(basename "$conf")")
            fi
        done < <(find "$NGINX_CONF_DIR" -maxdepth 1 -type f 2>/dev/null | sort)
    fi
    
    if [ ${#configs[@]} -eq 0 ]; then
        echo -e "${RED}❌ Нет конфигов в $NGINX_CONF_DIR${NC}"
        return 1
    fi
    
    echo -e "\n${BLUE}Выберите конфиг для ${action}:${NC}"
    for i in "${!configs[@]}"; do
        local status=""
        if [ -L "$NGINX_ENABLED_DIR/${configs[$i]}" ]; then
            status="${GREEN}[АКТИВЕН]${NC}"
        else
            status="${RED}[НЕАКТИВЕН]${NC}"
        fi
        echo -e "  $((i+1))) ${configs[$i]} $status"
    done
    echo -e "  0) Назад"
    
    read -p "Выберите номер: " choice
    
    if [ "$choice" == "0" ]; then
        return 1
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#configs[@]} ]; then
        selected_config="${configs[$((choice-1))]}"
        return 0
    else
        echo -e "${RED}❌ Неверный выбор${NC}"
        return 1
    fi
}

# Функция просмотра конфига
view_config() {
    local config_name="$1"
    local config_path="$NGINX_CONF_DIR/$config_name"
    
    clear_screen
    show_header
    
    echo -e "${BLUE}📄 ПРОСМОТР КОНФИГА: $config_name${NC}\n"
    
    if [ ! -f "$config_path" ]; then
        echo -e "${RED}❌ Конфиг не найден${NC}"
        pause_and_clear
        return 1
    fi
    
    echo -e "${CYAN}=== Содержимое конфига ===${NC}\n"
    echo -e "${YELLOW}"
    cat "$config_path"
    echo -e "${NC}"
    
    pause_and_clear
}

# Функция редактирования конфига
edit_config() {
    local config_name="$1"
    local config_path="$NGINX_CONF_DIR/$config_name"
    
    clear_screen
    show_header
    
    echo -e "${BLUE}✏️ РЕДАКТИРОВАНИЕ КОНФИГА: $config_name${NC}\n"
    
    if [ ! -f "$config_path" ]; then
        echo -e "${RED}❌ Конфиг не найден${NC}"
        pause_and_clear
        return 1
    fi
    
    create_backup "$config_name"
    echo -e "${BLUE}Открытие редактора...${NC}"
    sleep 1
    ${EDITOR:-nano} "$config_path"
    
    echo -e "\n${BLUE}Проверить конфиг после редактирования? (y/N):${NC}"
    read -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        clear_screen
        show_header
        if test_configuration; then
            echo -e "\n${BLUE}Перезагрузить nginx? (y/N):${NC}"
            read -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                reload_nginx
            fi
        fi
    fi
    
    log "Отредактирован конфиг: $config_name"
    pause_and_clear
}

# Функция удаления конфига
delete_config() {
    local config_name="$1"
    local domain="${config_name%.conf}"
    local config_path="$NGINX_CONF_DIR/$config_name"
    local enabled_path="$NGINX_ENABLED_DIR/$config_name"
    
    clear_screen
    show_header
    
    echo -e "${RED}⚠️  УДАЛЕНИЕ КОНФИГА: $config_name${NC}\n"
    
    if [ ! -f "$config_path" ]; then
        echo -e "${RED}❌ Конфиг не найден${NC}"
        pause_and_clear
        return 1
    fi
    
    echo -e "${RED}⚠️  ВНИМАНИЕ: Вы собираетесь удалить конфиг для домена $domain${NC}"
    read -p "Создать бэкап перед удалением? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_backup "$config_name"
    fi
    
    read -p "Удалить Let's Encrypt сертификаты для $domain? (y/N): " -n 1 -r
    echo
    local delete_ssl=false
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        delete_ssl=true
    fi
    
    read -p "Удалить директорию сайта $WWW_ROOT/$domain? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo rm -rf "$WWW_ROOT/$domain"
        echo -e "${GREEN}✅ Директория сайта удалена${NC}"
    fi
    
    if [ -L "$enabled_path" ]; then
        echo -e "${BLUE}Деактивация конфига...${NC}"
        sudo rm "$enabled_path" 2>/dev/null
    fi
    
    sudo rm "$config_path" 2>/dev/null
    
    # Удаляем сертификаты Let's Encrypt
    if [ "$delete_ssl" = true ] && [ -d "$SSL_DIR/$domain" ]; then
        echo -e "${BLUE}Удаление сертификатов Let's Encrypt...${NC}"
        sudo certbot delete --cert-name "$domain" --non-interactive 2>/dev/null
        echo -e "${GREEN}✅ Сертификаты удалены${NC}"
    fi
    
    if test_configuration && reload_nginx; then
        echo -e "\n${GREEN}✅ Конфиг для домена $domain удален!${NC}"
        log "Удален конфиг домена: $domain"
    else
        echo -e "\n${RED}❌ Ошибка при удалении${NC}"
    fi
    
    pause_and_clear
}

# Главная функция
main() {
    check_root
    
    while true; do
        clear_screen
        show_header
        show_menu
        
        read -p "Выберите действие [0-9/R]: " choice
        
        case $choice in
            1)
                if select_config "активации"; then
                    activate_config "$selected_config"
                fi
                ;;
            2)
                if select_config "деактивации"; then
                    deactivate_config "$selected_config"
                fi
                ;;
            3)
                show_status
                ;;
            4)
                create_any_config
                ;;
            5)
                if select_config "редактирования"; then
                    edit_config "$selected_config"
                fi
                ;;
            6)
                if select_config "просмотра"; then
                    view_config "$selected_config"
                fi
                ;;
            7)
                if select_config "удаления"; then
                    delete_config "$selected_config"
                fi
                ;;
            8)
                clear_screen
                show_header
                test_configuration
                pause_and_clear
                ;;
            9)
                clear_screen
                show_header
                reload_nginx
                pause_and_clear
                ;;
            [Rr])
                renew_all_certificates
                ;;
            0)
                echo -e "\n${GREEN}До свидания!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Неверный выбор!${NC}"
                sleep 1
                clear_screen
                ;;
        esac
    done
}

# Запуск
main "$@"