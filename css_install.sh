#!/bin/bash

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Функция для паузы с анимацией
function slow_pause {
    local seconds=${1:-2}
    local msg=${2:-"▶"}
    echo -ne "${CYAN}$msg${NC}"
    for ((i=1; i<=seconds; i++)); do
        sleep 1
        echo -ne "${CYAN}.${NC}"
    done
    echo ""
}

# Функция для медленного выполнения команды
function slow_execute {
    local cmd="$1"
    local msg="$2"
    
    echo -e "${YELLOW}⏳ $msg${NC}"
    sleep 1
    eval "$cmd"
    local result=$?
    
    if [ $result -eq 0 ]; then
        echo -e "${GREEN}✓ Готово${NC}"
    else
        echo -e "${RED}✗ Ошибка${NC}"
    fi
    sleep 1
    return $result
}

# Функция для пошагового вывода
function step_echo {
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}➤ $1${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    sleep 1.5
}

# Функция очистки экрана с заголовком
function clear_screen {
    clear
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${PURPLE} Counter-Strike: Source Server Manager${NC}"
    echo -e "${PURPLE}========================================${NC}"
    echo ""
    sleep 0.5
}

# Проверка на Ubuntu 24.04
OS_CHECK=$(lsb_release -i -s 2>/dev/null)
OS_VERSION=$(lsb_release -r -s 2>/dev/null)

if [ "$OS_CHECK" != "Ubuntu" ] || [ "$OS_VERSION" != "24.04" ]; then
    echo -e "${RED}Ошибка: Этот скрипт предназначен только для Ubuntu 24.04!${NC}"
    echo -e "${YELLOW}Обнаружено: $OS_CHECK $OS_VERSION${NC}"
    exit 1
fi

# Функция для проверки ввода числа
function validate_number {
    local num=$1
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Ошибка: введите число!${NC}"
        return 1
    fi
    return 0
}

# Функция для проверки IP адреса
function validate_ip {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a ip_parts <<< "$ip"
        for part in "${ip_parts[@]}"; do
            if [ $part -lt 0 ] || [ $part -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Функция для проверки доступности порта
function check_port {
    local port=$1
    if [[ $port -lt 1 || $port -gt 65535 ]]; then
        echo -e "${RED}Ошибка: порт должен быть в диапазоне 1-65535!${NC}"
        return 1
    fi
    
    if ss -tuln 2>/dev/null | grep -q ":$port "; then
        echo -e "${RED}Ошибка: порт $port уже занят!${NC}"
        return 1
    fi
    
    return 0
}

# Функция для установки плагинов (упрощенная версия)
function install_plugins {
    local username=$1
    local SOURCEMOD_DIR="/home/$username/csserver/cstrike/addons/sourcemod"
    
    if [ ! -d "$SOURCEMOD_DIR" ]; then
        echo -e "${RED}SourceMod не установлен! Невозможно установить плагины.${NC}"
        return 1
    fi
    
    clear_screen
    step_echo "Установка дополнительных плагинов"
    
    mkdir -p "$SOURCEMOD_DIR/plugins"
    mkdir -p "$SOURCEMOD_DIR/plugins/disabled"
    mkdir -p "$SOURCEMOD_DIR/scripting"
    mkdir -p "$SOURCEMOD_DIR/translations"
    
    echo -e "${CYAN}Доступные плагины для установки:${NC}"
    echo -e "${WHITE}0) Пропустить установку плагинов${NC}"
    echo ""
    
    local plugins=(
        "1|WeaponGiver|Выдача оружия|https://raw.githubusercontent.com/den112276/steamclientmod/main/sm_weapongiver_rus_1.01.smx|"
        "2|NoBlock|Проходить сквозь игроков своей команды|https://raw.githubusercontent.com/den112276/steamclientmod/main/noblock.smx|"
    )
    
    for plugin in "${plugins[@]}"; do
        IFS='|' read -r num name desc smx_url trans_url cfg_url <<< "$plugin"
        echo -e "${WHITE}$num) ${GREEN}$name${NC} - ${YELLOW}$desc${NC}"
    done
    
    echo ""
    echo -e "${CYAN}Введите номера плагинов через запятую или пробел (например: 1,3,5 или 1 3 5)${NC}"
    echo -e "${CYAN}Или введите диапазон (например: 1-5)${NC}"
    read -p "$(echo -e "${WHITE}Выберите плагины для установки: ${NC}")" plugin_choice
    
    if [[ "$plugin_choice" == "0" ]] || [[ -z "$plugin_choice" ]]; then
        echo -e "${YELLOW}Установка плагинов пропущена.${NC}"
        sleep 1
        return 0
    fi
    
    local selected_numbers=()
    IFS=', ' read -ra choices <<< "$plugin_choice"
    for choice in "${choices[@]}"; do
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            selected_numbers+=("$choice")
        elif [[ "$choice" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            for ((i=${BASH_REMATCH[1]}; i<=${BASH_REMATCH[2]}; i++)); do
                selected_numbers+=("$i")
            done
        fi
    done
    
    selected_numbers=($(echo "${selected_numbers[@]}" | tr ' ' '\n' | sort -nu | tr '\n' ' '))
    
    local installed_count=0
    local fail_count=0
    
    for num in "${selected_numbers[@]}"; do
        local found=0
        for plugin in "${plugins[@]}"; do
            IFS='|' read -r p_num p_name p_desc p_smx_url p_trans_url p_cfg_url <<< "$plugin"
            if [ "$p_num" -eq "$num" ]; then
                found=1
                echo ""
                echo -e "${CYAN}--- Установка плагина: $p_name ---${NC}"
                sleep 1
                
                echo -e "${YELLOW}Загрузка $p_name...${NC}"
                wget --timeout=30 --tries=3 --show-progress -O "$SOURCEMOD_DIR/plugins/${p_name}.smx" "$p_smx_url"
                slow_pause 1 "⏳ Проверка загрузки"
                
                if [ -f "$SOURCEMOD_DIR/plugins/${p_name}.smx" ] && [ -s "$SOURCEMOD_DIR/plugins/${p_name}.smx" ]; then
                    echo -e "${GREEN}✓ $p_name успешно загружен${NC}"
                    chown "$username":"$username" "$SOURCEMOD_DIR/plugins/${p_name}.smx"
                    installed_count=$((installed_count + 1))
                    sleep 1
                else
                    echo -e "${RED}✗ Ошибка загрузки $p_name${NC}"
                    rm -f "$SOURCEMOD_DIR/plugins/${p_name}.smx" 2>/dev/null
                    fail_count=$((fail_count + 1))
                fi
                break
            fi
        done
        if [ $found -eq 0 ]; then
            echo -e "${RED}Неверный номер плагина: $num${NC}"
            fail_count=$((fail_count + 1))
        fi
    done
    
    echo ""
    step_echo "Результат установки плагинов"
    echo -e "${GREEN}Успешно установлено: $installed_count${NC}"
    if [ $fail_count -gt 0 ]; then
        echo -e "${RED}Не удалось установить: $fail_count${NC}"
    fi
    sleep 2
    
    echo -e "${YELLOW}Для активации плагинов необходимо перезагрузить сервер или выполнить:${NC}"
    echo -e "${GREEN}sm plugins refresh${NC}"
    sleep 2
    
    return 0
}

# Функция для настройки администраторов
function configure_admins {
    local username=$1
    local ADMIN_FILE="/home/$username/csserver/cstrike/addons/sourcemod/configs/admins_simple.ini"
    
    clear_screen
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} Настройка администраторов сервера${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    mkdir -p "/home/$username/csserver/cstrike/addons/sourcemod/configs/"
    
    # Проверяем, существует ли уже файл с администраторами
    if [ -f "$ADMIN_FILE" ]; then
        echo -e "${YELLOW}Файл администраторов уже существует.${NC}"
        echo -e "${YELLOW}В текущем файле уже есть:${NC}"
        echo -e "${CYAN}----------------------------------------${NC}"
        # Показываем существующих администраторов (игнорируем комментарии и пустые строки)
        grep -v "^//" "$ADMIN_FILE" | grep -v "^$" | grep -v "^\*" | head -10
        echo -e "${CYAN}----------------------------------------${NC}"
        read -p "$(echo -e "${WHITE}Добавить администраторов к существующим? (y/n): ${NC}")" append_admins
        if [ "$append_admins" != "y" ]; then
            read -p "$(echo -e "${WHITE}Перезаписать существующий файл? (y/n): ${NC}")" overwrite_admins
            if [ "$overwrite_admins" != "y" ]; then
                echo -e "${YELLOW}Настройка администраторов пропущена.${NC}"
                return 0
            fi
            # Перезаписываем файл с заголовком
            cat > "$ADMIN_FILE" <<'EOF'
/**
 * admins_simple.ini
 * 
 * Форматы:
 *   "steam_id"     "flags"              "password"
 *   "!ip_address"  "immunity:flags"     "password"
 *   "name"         "flags"              "password"
 * 
 * Примеры:
 *   "STEAM_0:1:16"          "bce"                       // Steam ID с флагами
 *   "!127.0.0.1"            "99:z"                      // IP с иммунитетом 99 и root правами
 *   "BAILOPAN"              "abc"           "Gab3n"     // Никнейм с паролем
 * 
 * Флаги доступа:
 *   a - reservation (резервация слота)
 *   b - generic (общий доступ админа)
 *   c - kick (кик игроков)
 *   d - ban (бан игроков)
 *   e - unban (разбан игроков)
 *   f - slay (убить игрока)
 *   g - changemap (смена карты)
 *   h - cvars (доступ к консольным переменным)
 *   i - config (загрузка конфигов)
 *   j - chat (доступ к чату админов)
 *   k - vote (голосования)
 *   l - password (доступ к паролю сервера)
 *   m - rcon (доступ к RCON)
 *   n - custom1
 *   o - custom2
 *   p - custom3
 *   q - custom4
 *   r - custom5
 *   s - custom6
 *   t - custom7
 *   u - custom8
 *   z - root (полный доступ)
 * 
 * Иммунитет:
 *   Чем выше число, тем выше иммунитет (обычно от 0 до 99)
 *   99 - максимальный иммунитет (нельзя кикнуть/забанить)
 */

EOF
        fi
    else
        # Создаем новый файл с заголовком
        cat > "$ADMIN_FILE" <<'EOF'
/**
 * admins_simple.ini
 * 
 * Форматы:
 *   "steam_id"     "flags"              "password"
 *   "!ip_address"  "immunity:flags"     "password"
 *   "name"         "flags"              "password"
 * 
 * Примеры:
 *   "STEAM_0:1:16"          "bce"                       // Steam ID с флагами
 *   "!127.0.0.1"            "99:z"                      // IP с иммунитетом 99 и root правами
 *   "BAILOPAN"              "abc"           "Gab3n"     // Никнейм с паролем
 * 
 * Флаги доступа:
 *   a - reservation (резервация слота)
 *   b - generic (общий доступ админа)
 *   c - kick (кик игроков)
 *   d - ban (бан игроков)
 *   e - unban (разбан игроков)
 *   f - slay (убить игрока)
 *   g - changemap (смена карты)
 *   h - cvars (доступ к консольным переменным)
 *   i - config (загрузка конфигов)
 *   j - chat (доступ к чату админов)
 *   k - vote (голосования)
 *   l - password (доступ к паролю сервера)
 *   m - rcon (доступ к RCON)
 *   n - custom1
 *   o - custom2
 *   p - custom3
 *   q - custom4
 *   r - custom5
 *   s - custom6
 *   t - custom7
 *   u - custom8
 *   z - root (полный доступ)
 * 
 * Иммунитет:
 *   Чем выше число, тем выше иммунитет (обычно от 0 до 99)
 *   99 - максимальный иммунитет (нельзя кикнуть/забанить)
 */

EOF
    fi
    
    echo -e "${GREEN}Настройка администраторов сервера:${NC}"
    echo -e "${YELLOW}Введите данные администратора (можно добавить несколько)${NC}"
    echo -e "${CYAN}Поддерживаемые типы идентификации:${NC}"
    echo -e "${WHITE}1) Steam ID${NC}"
    echo -e "${WHITE}2) IP адрес (будет добавлен с префиксом !)${NC}"
    echo -e "${WHITE}3) Игровой ник${NC}"
    echo ""
    
    local admin_count=0
    while true; do
        echo ""
        echo -e "${CYAN}--- Администратор #$((admin_count+1)) ---${NC}"
        
        # Выбор типа идентификации
        while true; do
            read -p "$(echo -e "${WHITE}Выберите тип идентификации (1-3): ${NC}")" id_type
            case $id_type in
                1)
                    id_type_name="SteamID"
                    echo -e "${YELLOW}Пример SteamID: STEAM_0:1:16 или STEAM_0:0:123456789${NC}"
                    read -p "$(echo -e "${WHITE}Введите SteamID: ${NC}")" identifier
                    if [ -z "$identifier" ]; then
                        echo -e "${RED}SteamID не может быть пустым!${NC}"
                        continue
                    fi
                    identifier_formatted="$identifier"
                    break
                    ;;
                2)
                    id_type_name="IP адрес"
                    echo -e "${YELLOW}Пример IP: 192.168.1.100 или 92.124.139.225${NC}"
                    while true; do
                        read -p "$(echo -e "${WHITE}Введите IP адрес: ${NC}")" identifier
                        if validate_ip "$identifier"; then
                            # Добавляем восклицательный знак перед IP для SourceMod
                            identifier_formatted="!$identifier"
                            echo -e "${GREEN}IP адрес будет добавлен в формате: $identifier_formatted${NC}"
                            break
                        else
                            echo -e "${RED}Неверный формат IP адреса! Используйте формат: xxx.xxx.xxx.xxx${NC}"
                        fi
                    done
                    break
                    ;;
                3)
                    id_type_name="Никнейм"
                    echo -e "${YELLOW}Пример ника: BAILOPAN или Admin${NC}"
                    read -p "$(echo -e "${WHITE}Введите игровой ник: ${NC}")" identifier
                    if [ -z "$identifier" ]; then
                        echo -e "${RED}Никнейм не может быть пустым!${NC}"
                        continue
                    fi
                    identifier_formatted="$identifier"
                    break
                    ;;
                *)
                    echo -e "${RED}Неверный выбор!${NC}"
                    ;;
            esac
        done
        
        clear_screen
        echo -e "${GREEN}Настройка прав для $id_type_name: $identifier_formatted${NC}"
        echo ""
        
        # Выбор уровня доступа
        echo -e "${GREEN}Выберите уровень доступа:${NC}"
        echo -e "${WHITE}1) Root (полный доступ, флаг 'z')${NC}"
        echo -e "${WHITE}2) Root с иммунитетом 99 (для IP: 99:z)${NC}"
        echo -e "${WHITE}3) Администратор (смена карт, кик/бан, флаги 'bceg')${NC}"
        echo -e "${WHITE}4) Модератор (кик/бан, флаги 'bce')${NC}"
        echo -e "${WHITE}5) VIP игрок (резервация слота, флаг 'a')${NC}"
        echo -e "${WHITE}6) Свой набор флагов${NC}"
        
        local access_flags=""
        local immunity=""
        
        while true; do
            read -p "$(echo -e "${WHITE}Выберите уровень (1-6): ${NC}")" access_choice
            case $access_choice in
                1)
                    if [ "$id_type" = "2" ]; then
                        access_flags="z"
                        immunity="99"
                        access_flags_formatted="99:z"
                    else
                        access_flags="z"
                        access_flags_formatted="z"
                    fi
                    break
                    ;;
                2)
                    if [ "$id_type" = "2" ]; then
                        access_flags_formatted="99:z"
                    else
                        echo -e "${YELLOW}Для Steam ID и ников иммунитет указывается отдельным параметром${NC}"
                        read -p "$(echo -e "${WHITE}Введите уровень иммунитета (0-99, по умолчанию 0): ${NC}")" immunity
                        if [ -z "$immunity" ]; then
                            immunity="0"
                        fi
                        access_flags="z"
                        access_flags_formatted="z"
                    fi
                    break
                    ;;
                3)
                    if [ "$id_type" = "2" ]; then
                        access_flags_formatted="99:bceg"
                    else
                        access_flags="bceg"
                        access_flags_formatted="bceg"
                    fi
                    break
                    ;;
                4)
                    if [ "$id_type" = "2" ]; then
                        access_flags_formatted="99:bce"
                    else
                        access_flags="bce"
                        access_flags_formatted="bce"
                    fi
                    break
                    ;;
                5)
                    if [ "$id_type" = "2" ]; then
                        access_flags_formatted="99:a"
                    else
                        access_flags="a"
                        access_flags_formatted="a"
                    fi
                    break
                    ;;
                6)
                    echo -e "${YELLOW}Доступные флаги:${NC}"
                    echo "a - reservation (резервация слота)"
                    echo "b - generic (общий доступ админа)"
                    echo "c - kick (кик игроков)"
                    echo "d - ban (бан игроков)"
                    echo "e - unban (разбан игроков)"
                    echo "f - slay (убить игрока)"
                    echo "g - changemap (смена карты)"
                    echo "h - cvars (доступ к консольным переменным)"
                    echo "i - config (загрузка конфигов)"
                    echo "j - chat (доступ к чату админов)"
                    echo "k - vote (голосования)"
                    echo "l - password (доступ к паролю сервера)"
                    echo "m - rcon (доступ к RCON)"
                    echo "z - root (полный доступ)"
                    echo ""
                    read -p "$(echo -e "${WHITE}Введите флаги (например 'bce' или 'z'): ${NC}")" access_flags
                    if [ -n "$access_flags" ]; then
                        if [ "$id_type" = "2" ]; then
                            read -p "$(echo -e "${WHITE}Введите уровень иммунитета (0-99, по умолчанию 0): ${NC}")" immunity
                            if [ -z "$immunity" ]; then
                                immunity="0"
                            fi
                            access_flags_formatted="$immunity:$access_flags"
                        else
                            access_flags_formatted="$access_flags"
                            if [ "$access_choice" = "2" ] || [ "$access_choice" = "1" ]; then
                                read -p "$(echo -e "${WHITE}Введите уровень иммунитета (0-99, по умолчанию 0): ${NC}")" immunity
                                if [ -z "$immunity" ]; then
                                    immunity="0"
                                fi
                            fi
                        fi
                        break
                    else
                        echo -e "${RED}Флаги не могут быть пустыми!${NC}"
                    fi
                    ;;
                *)
                    echo -e "${RED}Неверный выбор!${NC}"
                    ;;
            esac
        done
        
        # Пароль (опционально) - не предлагаем для IP адресов
        local admin_pass=""
        if [ "$id_type" != "2" ]; then
            read -p "$(echo -e "${WHITE}Пароль (оставьте пустым если не нужен): ${NC}")" admin_pass
        else
            echo -e "${CYAN}Для IP адреса пароль не требуется${NC}"
            sleep 1
        fi
        
        # Формируем строку для admins_simple.ini
        local admin_line=""
        if [ -n "$admin_pass" ]; then
            # Для ника с паролем: "BAILOPAN" "abc" "Gab3n"
            # Для Steam ID с паролем: "STEAM_0:1:16" "bce" "password"
            admin_line="\"$identifier_formatted\" \"$access_flags_formatted\" \"$admin_pass\""
        else
            # Без пароля: "STEAM_0:1:16" "bce" или "!192.168.1.100" "99:z"
            admin_line="\"$identifier_formatted\" \"$access_flags_formatted\""
        fi
        
        # Проверяем, не существует ли уже такой администратор
        if grep -q "^\"$identifier_formatted\"" "$ADMIN_FILE" 2>/dev/null; then
            echo -e "${YELLOW}ВНИМАНИЕ: Администратор с идентификатором '$identifier_formatted' уже существует!${NC}"
            read -p "$(echo -e "${WHITE}Заменить? (y/n): ${NC}")" replace_admin
            if [ "$replace_admin" = "y" ]; then
                # Удаляем существующую запись
                sed -i "/^\"$identifier_formatted\"/d" "$ADMIN_FILE"
            else
                echo -e "${YELLOW}Пропускаем...${NC}"
                continue
            fi
        fi
        
        # Добавляем запись
        echo "$admin_line" >> "$ADMIN_FILE"
        
        echo -e "${GREEN}✓ Администратор ($id_type_name) добавлен:${NC}"
        echo -e "${GREEN}  Строка: $admin_line${NC}"
        admin_count=$((admin_count+1))
        
        read -p "$(echo -e "${WHITE}Добавить еще одного администратора? (y/n): ${NC}")" add_more
        if [ "$add_more" != "y" ]; then
            break
        fi
        clear_screen
        echo -e "${GREEN}Добавлен администратор #$admin_count${NC}"
        echo ""
    done
    
    if [ $admin_count -gt 0 ]; then
        echo -e "${GREEN}Добавлено/обновлено администраторов: $admin_count${NC}"
        chown "$username":"$username" "$ADMIN_FILE"
        echo -e "${YELLOW}Путь к файлу администраторов: $ADMIN_FILE${NC}"
        echo ""
        echo -e "${CYAN}Примеры правильных записей в файле:${NC}"
        echo -e "${WHITE}  \"STEAM_0:1:16\"          \"bce\"${NC}"
        echo -e "${WHITE}  \"!192.168.1.100\"        \"99:z\"${NC}"
        echo -e "${WHITE}  \"BAILOPAN\"              \"abc\"           \"Gab3n\"${NC}"
    else
        echo -e "${YELLOW}Не добавлено ни одного администратора.${NC}"
    fi
}

# Функция для очистки мертвых screen сессий
function clean_screen_sessions {
    clear_screen
    step_echo "Очистка мертвых screen сессий"
    
    read -p "$(echo -e "${WHITE}Введите имя пользователя сервера CSS: ${NC}")" username
    
    if id "$username" &>/dev/null; then
        echo -e "${YELLOW}Очистка сессий для пользователя $username...${NC}"
        sudo -u "$username" screen -wipe
        echo -e "${GREEN}✓ Мертвые сессии очищены${NC}"
        
        # Показать активные сессии
        echo -e "${CYAN}Активные сессии:${NC}"
        sudo -u "$username" screen -list
    else
        echo -e "${RED}Пользователь $username не найден!${NC}"
    fi
    
    sleep 3
    read -p "$(echo -e "${WHITE}Нажмите Enter для возврата в меню...${NC}")"
}

# Функция для удаления сервера CSS
function uninstall_css {
    clear_screen
    step_echo "Удаление сервера CSS"
    
    read -p "$(echo -e "${WHITE}Введите имя пользователя сервера CSS: ${NC}")" username
    
    if id "$username" &>/dev/null; then
        echo -e "${YELLOW}Поиск и остановка запущенных процессов...${NC}"
        slow_pause 2 "🔍 Поиск процессов"
        
        pids=$(pgrep -f "srcds_run.*cstrike" 2>/dev/null)
        if [ -n "$pids" ]; then
            echo -e "${YELLOW}Найдены процессы (PID: $pids), останавливаем...${NC}"
            for pid in $pids; do
                kill -9 $pid 2>/dev/null
                echo -e "${GREEN}  Остановлен процесс $pid${NC}"
                sleep 0.5
            done
            sleep 2
        fi
        
        if sudo -u "$username" screen -list 2>/dev/null | grep -q "csserver"; then
            echo -e "${YELLOW}Останавливаем сессии screen...${NC}"
            # Очищаем все сессии csserver
            sudo -u "$username" screen -wipe 2>/dev/null
            sudo -u "$username" screen -X -S csserver quit 2>/dev/null
            sleep 1
        fi
        
        echo -e "${YELLOW}Удаляем задачу из cron...${NC}"
        sudo -u "$username" crontab -r 2>/dev/null
        rm -f "/var/spool/cron/crontabs/$username" 2>/dev/null
        sleep 1
        
        if [ -d "/home/$username/csserver" ]; then
            echo -e "${YELLOW}Удаляем папку с сервером...${NC}"
            slow_pause 2 "🗑️  Удаление файлов"
            rm -rf "/home/$username/csserver"
            echo -e "${GREEN}✓ Папка сервера удалена${NC}"
        fi
        
        if [ -f "/home/$username/start_css.sh" ]; then
            echo -e "${YELLOW}Удаляем скрипт запуска...${NC}"
            rm -f "/home/$username/start_css.sh"
            sleep 0.5
        fi
        
        # Удаление SteamCMD
        if [ -d "/opt/steamcmd" ]; then
            echo -e "${YELLOW}Удаляем SteamCMD из /opt/steamcmd...${NC}"
            slow_pause 2 "🗑️  Удаление SteamCMD"
            rm -rf "/opt/steamcmd"
            echo -e "${GREEN}✓ SteamCMD удален${NC}"
        fi
        
        user_processes=$(pgrep -u "$username" 2>/dev/null)
        if [ -z "$user_processes" ]; then
            read -p "$(echo -e "${WHITE}Удалить пользователя $username? (y/n): ${NC}")" del_user
            if [ "$del_user" = "y" ]; then
                echo -e "${YELLOW}Удаляем пользователя $username...${NC}"
                userdel -r "$username" 2>/dev/null
                sleep 1
                if id "$username" &>/dev/null; then
                    echo -e "${RED}Не удалось удалить пользователя!${NC}"
                else
                    echo -e "${GREEN}Пользователь удалён${NC}"
                fi
            fi
        fi
        
        echo -e "${GREEN}✓ Удаление сервера CSS завершено!${NC}"
    else
        echo -e "${RED}Пользователь $username не найден!${NC}"
    fi
    
    sleep 2
    read -p "$(echo -e "${WHITE}Нажмите Enter для возврата в меню...${NC}")"
    show_menu
}

# Функция для установки сервера CSS с повторами
function install_css_server_with_retry {
    local username=$1
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo -e "${YELLOW}Попытка установки сервера CSS #$attempt...${NC}"
        sleep 1
        
        if [ -d "/home/$username/csserver" ]; then
            echo -e "${YELLOW}Очищаем старую директорию...${NC}"
            rm -rf "/home/$username/csserver"
            sleep 1
        fi
        
        slow_execute "sudo -u \"$username\" /opt/steamcmd/steamcmd.sh +force_install_dir \"/home/$username/csserver\" +login anonymous +app_update 232330 validate +quit" "Установка через SteamCMD"
        
        if [ -f "/home/$username/csserver/srcds_run" ]; then
            echo -e "${GREEN}✓ Сервер CSS успешно установлен!${NC}"
            sleep 1
            return 0
        else
            echo -e "${RED}Ошибка установки (попытка $attempt из $max_attempts)${NC}"
            attempt=$((attempt + 1))
            
            if [ $attempt -le $max_attempts ]; then
                echo -e "${YELLOW}Повторная попытка через 10 секунд...${NC}"
                slow_pause 10 "⏳ Ожидание перед повтором"
            fi
        fi
    done
    
    echo -e "${RED}Не удалось установить сервер CSS после $max_attempts попыток!${NC}"
    return 1
}

# Функция для настройки ботов
function configure_bots {
    local SERVER_DIR=$1
    
    clear_screen
    step_echo "Настройка ботов"
    
    read -p "$(echo -e "${WHITE}Включить ботов на сервере? (y/n): ${NC}")" enable_bots
    
    if [ "$enable_bots" = "y" ]; then
        while true; do
            read -p "$(echo -e "${WHITE}Введите количество ботов (1-32): ${NC}")" bot_count
            validate_number "$bot_count" && [ "$bot_count" -ge 1 ] && [ "$bot_count" -le 32 ] && break
            echo -e "${RED}Неверное количество. Введите число от 1 до 32.${NC}"
        done
        
        echo -e "${GREEN}Выберите сложность ботов:${NC}"
        echo -e "${WHITE}1) Легкие${NC}"
        echo -e "${WHITE}2) Средние${NC}"
        echo -e "${WHITE}3) Сложные${NC}"
        echo -e "${WHITE}4) Эксперты${NC}"
        
        while true; do
            read -p "$(echo -e "${WHITE}Выберите уровень (1-4): ${NC}")" bot_difficulty
            validate_number "$bot_difficulty" && [ "$bot_difficulty" -ge 1 ] && [ "$bot_difficulty" -le 4 ] && break
            echo -e "${RED}Неверный выбор!${NC}"
        done
        
        local bot_config=(
            ""
            "// Настройки ботов"
            "bot_add \"$bot_count\""
            "bot_difficulty \"$((bot_difficulty-1))\""
            "bot_quota \"$bot_count\""
            "bot_quota_mode \"fill\""
        )
        
        for setting in "${bot_config[@]}"; do
            echo "$setting" >> "$SERVER_DIR/server.cfg"
        done
        
        echo -e "${GREEN}✓ Настройки ботов добавлены${NC}"
    else
        echo -e "${YELLOW}Боты не будут добавлены${NC}"
    fi
    sleep 1
}

# Основная функция установки
function install_css {
    declare -a maps=(
        "de_dust2" "de_inferno" "de_nuke" "de_train" "de_aztec"
        "de_port" "cs_office" "cs_italy" "cs_havana" "cs_assault"
    )
    
    declare -a slots_options=(8 12 16 20 24 32)
    
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Этот скрипт должен запускаться с правами root!${NC}"
        exit 1
    fi
    
    ARCH=$(uname -m)
    if [ "$ARCH" != "x86_64" ]; then
        echo -e "${YELLOW}Внимание: рекомендуется 64-битная система!${NC}"
        read -p "$(echo -e "${WHITE}Продолжить? (y/n): ${NC}")" choice
        if [ "$choice" != "y" ]; then
            exit 1
        fi
    fi
    
    clear_screen
    step_echo "Установка зависимостей"
    
    slow_execute "apt-get update" "Обновление списка пакетов"
    slow_execute "dpkg --add-architecture i386" "Включение 32-битной архитектуры"
    slow_execute "apt-get update" "Обновление списка пакетов (32-bit)"
    
    echo -e "${YELLOW}Установка необходимых пакетов...${NC}"
    slow_pause 2 "📦 Подготовка"
    
    apt-get install -y wget screen cron curl net-tools
    echo -e "${GREEN}✓ Базовые пакеты установлены${NC}"
    sleep 1
    
    apt-get install -y lib32gcc-s1 lib32stdc++6
    echo -e "${GREEN}✓ 32-битные библиотеки установлены${NC}"
    sleep 1
    
    apt-get install -y libcurl4t64:i386 libtinfo6:i386 libncurses6:i386
    echo -e "${GREEN}✓ Дополнительные библиотеки установлены${NC}"
    sleep 1
    
    clear_screen
    step_echo "Создание пользователя"
    
    while true; do
        read -p "$(echo -e "${WHITE}Введите имя пользователя для сервера: ${NC}")" username
        if [ -z "$username" ]; then
            echo -e "${RED}Имя не может быть пустым!${NC}"
        elif [ "$username" = "root" ]; then
            echo -e "${RED}Нельзя использовать root!${NC}"
        else
            break
        fi
    done
    
    if id "$username" &>/dev/null; then
        echo -e "${YELLOW}Пользователь $username уже существует${NC}"
    else
        slow_execute "useradd -m -s /bin/bash $username" "Создание пользователя $username"
    fi
    sleep 1
    
    clear_screen
    step_echo "Основные настройки сервера"
    
    while true; do
        read -p "$(echo -e "${WHITE}Введите название сервера: ${NC}")" server_name
        [ -n "$server_name" ] && break
        echo -e "${RED}Название не может быть пустым!${NC}"
    done
    
    while true; do
        read -p "$(echo -e "${WHITE}Введите порт сервера (по умолчанию 27015): ${NC}")" port
        if [ -z "$port" ]; then
            port=27015
            break
        fi
        validate_number "$port" && check_port "$port" && break
    done
    
    echo -e "${GREEN}Доступные варианты слотов:${NC}"
    for i in "${!slots_options[@]}"; do 
        printf "${WHITE}%d) %d\n${NC}" "$((i+1))" "${slots_options[$i]}"
    done
    
    while true; do
        read -p "$(echo -e "${WHITE}Выберите количество слотов (по умолчанию 3 - 16): ${NC}")" slot_choice
        if [ -z "$slot_choice" ]; then
            slots=16
            break
        fi
        if validate_number "$slot_choice" && [ "$slot_choice" -ge 1 ] && [ "$slot_choice" -le "${#slots_options[@]}" ]; then
            slots=${slots_options[$((slot_choice-1))]}
            break
        fi
        echo -e "${RED}Неверный выбор!${NC}"
    done
    
    echo -e "${GREEN}Доступные карты:${NC}"
    for i in "${!maps[@]}"; do 
        printf "${WHITE}%d) %s\n${NC}" "$((i+1))" "${maps[$i]}"
    done
    
    while true; do
        read -p "$(echo -e "${WHITE}Выберите стартовую карту (по умолчанию 1 - de_dust2): ${NC}")" map_choice
        if [ -z "$map_choice" ]; then
            start_map="de_dust2"
            break
        fi
        if validate_number "$map_choice" && [ "$map_choice" -ge 1 ] && [ "$map_choice" -le "${#maps[@]}" ]; then
            start_map=${maps[$((map_choice-1))]}
            break
        fi
        echo -e "${RED}Неверный выбор!${NC}"
    done
    
    clear_screen
    step_echo "Установка SteamCMD"
    
    slow_execute "mkdir -p /opt/steamcmd" "Создание директории"
    cd /opt/steamcmd || exit
    
    if [ ! -f steamcmd_linux.tar.gz ]; then
        slow_execute "wget https://raw.githubusercontent.com/den112276/steamclientmod/main/steamcmd_linux.tar.gz" "Загрузка SteamCMD"
    fi
    
    slow_execute "tar -xvzf steamcmd_linux.tar.gz" "Распаковка SteamCMD"
    slow_execute "chown -R $username:$username /opt/steamcmd" "Настройка прав"
    
    echo -e "${YELLOW}Первичная инициализация SteamCMD...${NC}"
    slow_pause 2 "⚙️ Настройка"
    sudo -u "$username" /opt/steamcmd/steamcmd.sh +quit
    sleep 1
    
    clear_screen
    step_echo "Установка сервера CSS"
    
    if ! install_css_server_with_retry "$username"; then
        echo -e "${RED}Не удалось установить сервер CSS. Проверьте подключение.${NC}"
        exit 1
    fi
    
    clear_screen
    step_echo "Модификация файлов сервера"
    
    BIN_DIR="/home/$username/csserver/bin"
    
    if [ -f "$BIN_DIR/steamclient.so" ]; then
        slow_execute "mv \"$BIN_DIR/steamclient.so\" \"$BIN_DIR/steamclient_valve.so\"" "Переименование оригинального steamclient.so"
    fi
    
    slow_execute "wget --timeout=30 --tries=3 -O \"$BIN_DIR/steamclient.so\" https://raw.githubusercontent.com/den112276/steamclientmod/main/steamclient.so" "Загрузка модифицированного steamclient.so"
    if [ -f "$BIN_DIR/steamclient.so" ]; then
        chown "$username":"$username" "$BIN_DIR/steamclient.so"
        echo -e "${GREEN}✓ steamclient.so загружен${NC}"
    fi
    sleep 1
    
    slow_execute "wget --timeout=30 --tries=3 -O \"/home/$username/csserver/rev.ini\" https://raw.githubusercontent.com/den112276/steamclientmod/main/rev.ini" "Загрузка rev.ini"
    if [ -f "/home/$username/csserver/rev.ini" ]; then
        chown "$username":"$username" "/home/$username/csserver/rev.ini"
        echo -e "${GREEN}✓ rev.ini загружен${NC}"
    fi
    sleep 1
    
    CSTRIKE_DIR="/home/$username/csserver/cstrike"
    
    echo -e "${YELLOW}Установка MetaMod...${NC}"
    wget --timeout=30 --tries=3 -O "$CSTRIKE_DIR/mm.tar.gz" https://raw.githubusercontent.com/den112276/steamclientmod/main/mm.tar.gz
    if [ -f "$CSTRIKE_DIR/mm.tar.gz" ]; then
        tar -xvzf "$CSTRIKE_DIR/mm.tar.gz" -C "$CSTRIKE_DIR" 2>/dev/null
        rm -f "$CSTRIKE_DIR/mm.tar.gz"
        echo -e "${GREEN}✓ MetaMod установлен${NC}"
    fi
    sleep 1
    
    echo -e "${YELLOW}Установка SourceMod...${NC}"
    wget --timeout=30 --tries=3 -O "$CSTRIKE_DIR/sm.tar.gz" https://raw.githubusercontent.com/den112276/steamclientmod/main/sm.tar.gz
    if [ -f "$CSTRIKE_DIR/sm.tar.gz" ]; then
        tar -xvzf "$CSTRIKE_DIR/sm.tar.gz" -C "$CSTRIKE_DIR" 2>/dev/null
        rm -f "$CSTRIKE_DIR/sm.tar.gz"
        echo -e "${GREEN}✓ SourceMod установлен${NC}"
    fi
    sleep 1
    
    chown -R "$username":"$username" "$CSTRIKE_DIR"
    
    SERVER_DIR="/home/$username/csserver/cstrike/cfg"
    mkdir -p "$SERVER_DIR"
    
    step_echo "Создание конфигурационных файлов"
    
    cat > "$SERVER_DIR/server.cfg" <<EOF
hostname "$server_name"
sv_password ""
sv_region 255
sv_lan 0
sv_maxplayers $slots
sv_contact "admin@example.com"
mp_timelimit 30
mp_freezetime 0
mp_roundtime 2.5
mp_startmoney 1000
mp_c4timer 25
mp_autoteambalance 1
mp_autokick 0
sv_cheats 0
log on
mapcyclefile "mapcycle.txt"
sv_allowdownload 1
sv_allowupload 1
sv_minrate 20000
sv_maxrate 30000
sv_mincmdrate 30
sv_maxcmdrate 101
sv_minupdaterate 30
sv_maxupdaterate 101
EOF
    echo -e "${GREEN}✓ server.cfg создан${NC}"
    sleep 1
    
    configure_bots "$SERVER_DIR"
    
    printf "%s\n" "${maps[@]}" > "$SERVER_DIR/mapcycle.txt"
    echo -e "${GREEN}✓ mapcycle.txt создан${NC}"
    sleep 1
    
    if [ -d "/home/$username/csserver/cstrike/addons/sourcemod" ]; then
        echo -e "${GREEN}SourceMod обнаружен${NC}"
        sleep 1
        configure_admins "$username"
        install_plugins "$username"
    else
        echo -e "${RED}SourceMod не установлен!${NC}"
    fi
    
    clear_screen
    step_echo "Создание скриптов запуска"
    
    START_SCRIPT="/home/$username/start_css.sh"
    cat > "$START_SCRIPT" <<EOF
#!/bin/bash

# Очистка мертвых screen сессий
screen -wipe 2>/dev/null

# Проверка существующей сессии
if ! screen -list 2>/dev/null | grep -q "csserver.*Detached"; then
    # Остановка старых процессов если есть
    pkill -f "srcds_linux.*cstrike" 2>/dev/null
    sleep 1
    
    cd "/home/$username/csserver"
    screen -dmS csserver ./srcds_run -game cstrike -console +map $start_map -maxplayers $slots -port $port
    echo "\$(date): Сервер CSS запущен" >> /home/$username/csserver/start.log
else
    echo "\$(date): Сервер CSS уже запущен" >> /home/$username/csserver/start.log
fi
EOF
    
    chmod +x "$START_SCRIPT"
    chown -R "$username":"$username" "/home/$username/csserver"
    chown "$username":"$username" "$START_SCRIPT"
    echo -e "${GREEN}✓ Скрипт запуска создан${NC}"
    sleep 1
    
    echo -e "${YELLOW}Настройка автозапуска...${NC}"
    CRON_JOB="@reboot /bin/bash $START_SCRIPT > /home/$username/csserver/cron.log 2>&1"
    
    if ! sudo -u "$username" crontab -l 2>/dev/null | grep -q "$START_SCRIPT"; then
        (sudo -u "$username" crontab -l 2>/dev/null; echo "$CRON_JOB") | sudo -u "$username" crontab -
        echo -e "${GREEN}✓ Задача добавлена в cron${NC}"
    fi
    sleep 1
    
    clear_screen
    step_echo "Запуск сервера"
    
    # Очистка мертвых screen сессий перед запуском
    echo -e "${YELLOW}Очистка старых screen сессий...${NC}"
    sudo -u "$username" screen -wipe 2>/dev/null
    sleep 1
    
    # Остановка старых процессов
    pkill -f "srcds_linux.*cstrike" 2>/dev/null
    sudo -u "$username" screen -X -S csserver quit 2>/dev/null
    sleep 2
    
    echo -e "${YELLOW}Запуск сервера CSS...${NC}"
    sudo -u "$username" bash -c "cd /home/$username/csserver && screen -dmS csserver ./srcds_run -game cstrike -console +map $start_map -maxplayers $slots -port $port"
    
    echo -n "Ожидание запуска сервера"
    local max_wait=30
    local waited=0
    local started=0
    
    while [ $waited -lt $max_wait ]; do
        sleep 2
        waited=$((waited + 2))
        echo -n "."
        
        if pgrep -f "srcds_linux.*cstrike" > /dev/null || pgrep -f "srcds_run.*cstrike" > /dev/null; then
            started=1
            break
        fi
    done
    
    echo ""
    
    # Проверка создания screen сессии
    if sudo -u "$username" screen -list 2>/dev/null | grep -q "csserver.*Detached"; then
        echo -e "${GREEN}✓ Screen сессия успешно создана${NC}"
    else
        echo -e "${RED}✗ Screen сессия не создана!${NC}"
        echo -e "${YELLOW}Проверьте ошибки в логах:${NC}"
        sudo -u "$username" tail -20 "/home/$username/csserver/cron.log" 2>/dev/null
    fi
    
    # Получаем IP адрес сервера
    SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(curl -s --max-time 5 ipinfo.io/ip 2>/dev/null)
    fi
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(hostname -I | awk '{print $1}')
    fi
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="Не удалось определить"
    fi
    
    if [ $started -eq 1 ]; then
        echo -e "${GREEN}✓ Сервер успешно запущен!${NC}"
        sleep 1
        
        if sudo -u "$username" screen -list 2>/dev/null | grep -q "csserver"; then
            echo -e "${GREEN}✓ Screen сессия активна${NC}"
            echo -e "${GREEN}✓ Подключение: sudo -u $username screen -r csserver${NC}"
        fi
        
        if ss -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "${GREEN}✓ Сервер слушает порт $port${NC}"
        fi
    else
        echo -e "${RED}✗ Сервер не запустился!${NC}"
        echo -e "${YELLOW}Проверьте логи:${NC}"
        sudo -u "$username" tail -30 "/home/$username/csserver/cron.log" 2>/dev/null
    fi
    
    echo ""
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${PURPLE} Установка завершена!${NC}"
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${WHITE}Название сервера: ${GREEN}$server_name${NC}"
    echo -e "${WHITE}IP адрес сервера: ${GREEN}$SERVER_IP${NC}"
    echo -e "${WHITE}Порт: ${GREEN}$port${NC}"
    echo -e "${WHITE}Слоты: ${GREEN}$slots${NC}"
    echo -e "${WHITE}Стартовая карта: ${GREEN}$start_map${NC}"
    echo ""
    echo -e "${WHITE}Для подключения к серверу в игре:${NC}"
    echo -e "${GREEN}connect $SERVER_IP:$port${NC}"
    echo ""
    echo -e "${WHITE}Для подключения к консоли сервера:${NC}"
    echo -e "${GREEN}sudo -u $username screen -r csserver${NC}"
    echo -e "${YELLOW}Для выхода из консоли: Ctrl+A затем D${NC}"
    echo ""
    echo -e "${GREEN}Сервер будет автоматически запускаться при загрузке системы${NC}"
    
    sleep 3
    read -p "$(echo -e "${WHITE}Нажмите Enter для возврата в меню...${NC}")"
    show_menu
}

# Главное меню
function show_menu {
    while true; do
        clear
        echo -e "${PURPLE}========================================${NC}"
        echo -e "${PURPLE} Меню управления сервером Counter-Strike: Source${NC}"
        echo -e "${PURPLE}========================================${NC}"
        echo -e "${WHITE}1) Установить сервер CSS${NC}"
        echo -e "${WHITE}2) Удалить сервер CSS${NC}"
        echo -e "${WHITE}3) Очистить мертвые screen сессии${NC}"
        echo -e "${WHITE}4) Выход${NC}"
        echo -e "${PURPLE}========================================${NC}"
        
        read -p "$(echo -e "${WHITE}Выберите действие [1-4]: ${NC}")" choice
        
        case $choice in
            1) install_css ;;
            2) uninstall_css ;;
            3) clean_screen_sessions ;;
            4)
                clear
                echo -e "${GREEN}Выход...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный выбор. Попробуйте снова.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Обработка аргументов командной строки
if [ "$1" = "--uninstall" ] || [ "$1" = "-u" ]; then
    uninstall_css
elif [ "$1" = "--install" ] || [ "$1" = "-i" ]; then
    install_css
elif [ "$1" = "--clean" ] || [ "$1" = "-c" ]; then
    clean_screen_sessions
elif [ "$1" = "--menu" ] || [ "$1" = "-m" ]; then
    show_menu
else
    show_menu
fi