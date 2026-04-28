#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════
# Скрипт автоматического выбора ближайшего зеркала Ubuntu
# Версия: 3.4 - С очисткой экрана и циклическим меню
# ═══════════════════════════════════════════════════════════════════════════

# Цветовая палитра
declare -r RED='\u001B[0;31m'
declare -r GREEN='\u001B[0;32m'
declare -r YELLOW='\u001B[1;33m'
declare -r BLUE='\u001B[1;94m'
declare -r MAGENTA='\u001B[0;35m'
declare -r CYAN='\u001B[1;96m'
declare -r WHITE='\u001B[1;37m'
declare -r GRAY='\u001B[1;37m'
declare -r BOLD='\u001B[1m'
declare -r DIM='\u001B[2m'
declare -r RESET='\u001B[0m'

# Иконки
declare -r ICON_CHECK="✓"
declare -r ICON_CROSS="✗"
declare -r ICON_TROPHY="🏆"
declare -r ICON_ROCKET="🚀"
declare -r ICON_GEAR="⚙"
declare -r ICON_CLOCK="⏱"
declare -r ICON_GLOBE="🌍"
declare -r ICON_BACKUP="💾"
declare -r ICON_RESTORE="♻"
declare -r ICON_DELETE="🗑"
declare -r ICON_LIST="📋"
declare -r ICON_MANUAL="✍"
declare -r ICON_AUTO="🎯"

# Глобальные переменные
UBUNTU_VERSION=""
UBUNTU_NUMERIC=""

# Функции форматирования
print_header() {
    echo -e "\n${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET} ${BOLD}${WHITE}$1${RESET}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════╝${RESET}\n"
}

print_section() {
    echo -e "\n${BOLD}${BLUE}▶ $1${RESET}\n"
}

print_success() {
    echo -e "${GREEN}${ICON_CHECK}${RESET} $1"
}

print_error() {
    echo -e "${RED}${ICON_CROSS}${RESET} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${RESET} $1"
}

print_info() {
    echo -e "${CYAN}${ICON_GEAR}${RESET} $1"
}

print_separator() {
    echo -e "${GRAY}───────────────────────────────────────────────────────────────${RESET}"
}

pause_screen() {
    echo -e -n "\n${GRAY}Нажмите Enter для продолжения...${RESET}"
    read
}

# ═══════════════════════════════════════════════════════════════════════════
# ФУНКЦИИ УПРАВЛЕНИЯ БЭКАПАМИ
# ═══════════════════════════════════════════════════════════════════════════

list_backups() {
    clear
    print_section "${ICON_LIST} Список резервных копий"
    
    backups=($(ls -t /etc/apt/sources.list.backup.* 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "Резервные копии не найдены"
        return 1
    fi
    
    echo -e "${BOLD}Найдено резервных копий: ${GREEN}${#backups[@]}${RESET}\n"
    
    for i in "${!backups[@]}"; do
        file="${backups[$i]}"
        timestamp=$(echo "$file" | grep -oP '\d{8}_\d{6}')
        date_formatted=$(date -d "${timestamp:0:8} ${timestamp:9:2}:${timestamp:11:2}:${timestamp:13:2}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$timestamp")
        size=$(du -h "$file" | cut -f1)
        
        mirror_info=$(grep "# Зеркало:" "$file" 2>/dev/null | sed 's/# Зеркало: //')
        
        printf "${GRAY}%2d.${RESET} ${WHITE}%s${RESET} ${CYAN}(%s)${RESET}\n" "$((i+1))" "$date_formatted" "$size"
        
        if [ -n "$mirror_info" ]; then
            echo -e "    ${DIM}Зеркало: ${mirror_info}${RESET}"
        fi
        
        echo ""
    done
    
    return 0
}

restore_backup() {
    clear
    print_section "${ICON_RESTORE} Восстановление из резервной копии"
    
    backups=($(ls -t /etc/apt/sources.list.backup.* 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_error "Резервные копии не найдены"
        pause_screen
        return 1
    fi
    
    for i in "${!backups[@]}"; do
        file="${backups[$i]}"
        timestamp=$(echo "$file" | grep -oP '\d{8}_\d{6}')
        date_formatted=$(date -d "${timestamp:0:8} ${timestamp:9:2}:${timestamp:11:2}:${timestamp:13:2}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$timestamp")
        mirror_info=$(grep "# Зеркало:" "$file" 2>/dev/null | sed 's/# Зеркало: //')
        
        printf "${GRAY}%2d.${RESET} ${WHITE}%s${RESET}\n" "$((i+1))" "$date_formatted"
        if [ -n "$mirror_info" ]; then
            echo -e "    ${DIM}Зеркало: ${mirror_info}${RESET}"
        fi
        echo ""
    done
    
    echo -e -n "${YELLOW}Введите номер резервной копии для восстановления (0 для отмены):${RESET} "
    read backup_choice
    
    if [[ ! "$backup_choice" =~ ^[0-9]+$ ]] || [ "$backup_choice" -lt 1 ] || [ "$backup_choice" -gt ${#backups[@]} ]; then
        print_warning "Отменено"
        pause_screen
        return 1
    fi
    
    idx=$((backup_choice - 1))
    selected_backup="${backups[$idx]}"
    
    echo -e -n "${YELLOW}Подтвердите восстановление (y/n):${RESET} "
    read confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Отменено"
        pause_screen
        return 1
    fi
    
    current_backup="/etc/apt/sources.list.backup.before_restore.$(date +%Y%m%d_%H%M%S)"
    cp /etc/apt/sources.list "$current_backup"
    
    cp "$selected_backup" /etc/apt/sources.list
    
    print_success "Резервная копия восстановлена"
    print_info "Текущая версия сохранена: ${BLUE}$current_backup${RESET}"
    
    echo -e -n "\n${YELLOW}Обновить кеш пакетов? (y/n):${RESET} "
    read update_confirm
    
    if [[ "$update_confirm" =~ ^[Yy]$ ]]; then
        print_info "Обновление кеша пакетов..."
        if apt update > /dev/null 2>&1; then
            print_success "Кеш обновлен успешно"
        else
            print_error "Ошибка обновления кеша"
        fi
    fi
    
    pause_screen
    return 0
}

delete_backups() {
    clear
    print_section "${ICON_DELETE} Удаление резервных копий"
    
    backups=($(ls -t /etc/apt/sources.list.backup.* 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_error "Резервные копии не найдены"
        pause_screen
        return 1
    fi
    
    list_backups
    
    echo -e "${BOLD}Опции удаления:${RESET}"
    echo -e "  ${CYAN}1.${RESET} Удалить конкретную резервную копию"
    echo -e "  ${CYAN}2.${RESET} Удалить все резервные копии старше N дней"
    echo -e "  ${CYAN}3.${RESET} Удалить все резервные копии (кроме последней)"
    echo -e "  ${CYAN}0.${RESET} Отмена"
    
    echo -e -n "\n${YELLOW}Выберите опцию:${RESET} "
    read delete_option
    
    case "$delete_option" in
        1)
            echo -e -n "${YELLOW}Введите номер резервной копии для удаления:${RESET} "
            read backup_num
            
            if [[ ! "$backup_num" =~ ^[0-9]+$ ]] || [ "$backup_num" -lt 1 ] || [ "$backup_num" -gt ${#backups[@]} ]; then
                print_error "Неверный номер"
                pause_screen
                return 1
            fi
            
            idx=$((backup_num - 1))
            selected_backup="${backups[$idx]}"
            
            echo -e -n "${RED}Подтвердите удаление (y/n):${RESET} "
            read confirm
            
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                rm "$selected_backup"
                print_success "Резервная копия удалена"
            else
                print_warning "Отменено"
            fi
            ;;
        2)
            echo -e -n "${YELLOW}Удалить копии старше (дней):${RESET} "
            read days
            
            if [[ ! "$days" =~ ^[0-9]+$ ]]; then
                print_error "Неверное число"
                pause_screen
                return 1
            fi
            
            deleted_count=0
            for backup in "${backups[@]}"; do
                if [ $(find "$backup" -mtime +$days 2>/dev/null | wc -l) -gt 0 ]; then
                    rm "$backup"
                    ((deleted_count++))
                fi
            done
            
            print_success "Удалено резервных копий: ${BOLD}$deleted_count${RESET}"
            ;;
        3)
            echo -e -n "${RED}Подтвердите удаление всех копий кроме последней (y/n):${RESET} "
            read confirm
            
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                deleted_count=0
                for i in "${!backups[@]}"; do
                    if [ $i -gt 0 ]; then
                        rm "${backups[$i]}"
                        ((deleted_count++))
                    fi
                done
                print_success "Удалено резервных копий: ${BOLD}$deleted_count${RESET}"
                print_info "Последняя резервная копия сохранена"
            else
                print_warning "Отменено"
            fi
            ;;
        0|*)
            print_warning "Отменено"
            ;;
    esac
    
    pause_screen
    return 0
}

show_backup_menu() {
    while true; do
        clear
        print_header "${ICON_BACKUP} УПРАВЛЕНИЕ РЕЗЕРВНЫМИ КОПИЯМИ"
        
        echo -e "${BOLD}Доступные операции:${RESET}\n"
        echo -e "  ${CYAN}1.${RESET} ${ICON_LIST} Показать список резервных копий"
        echo -e "  ${CYAN}2.${RESET} ${ICON_RESTORE} Восстановить из резервной копии"
        echo -e "  ${CYAN}3.${RESET} ${ICON_DELETE} Удалить резервные копии"
        echo -e "  ${CYAN}0.${RESET} Вернуться в главное меню"
        
        echo -e -n "\n${YELLOW}Выберите действие:${RESET} "
        read backup_action
        
        case "$backup_action" in
            1)
                list_backups
                pause_screen
                ;;
            2)
                restore_backup
                ;;
            3)
                delete_backups
                ;;
            0)
                return 0
                ;;
            *)
                print_error "Неверный выбор"
                sleep 1
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════════
# СПИСОК ЗЕРКАЛ
# ═══════════════════════════════════════════════════════════════════════════

MIRROR_NAMES=(
    "Yandex (RU)"
    "Truenetwork (RU)"
    "Selectel MSK (RU)"
    "Selectel SPB (RU)"
    "Selectel Samara (RU)"
    "Timeweb (RU)"
    "DataLine (RU)"
    "RU Main"
    "KZ Main"
    "Main Archive"
    "UK Main"
    "DE Main"
    "NL Main"
    "FR Main"
    "SE Main"
    "IT Main"
    "PL Main"
    "Kernel.org"
    "US Main"
    "MIT (US)"
    "AU Main"
    "CN Main"
    "JP Main"
    "SG Main"
    "IN Main"
)

MIRROR_URLS=(
    "mirror.yandex.ru/ubuntu"
    "mirror.truenetwork.ru/ubuntu"
    "mirror.msk.selectel.ru/ubuntu"
    "mirror.spb.selectel.ru/ubuntu"
    "mirror.samara.selectel.ru/ubuntu"
    "mirror.timeweb.ru/ubuntu"
    "mirror.dataline.net/ubuntu"
    "ru.archive.ubuntu.com/ubuntu"
    "kz.archive.ubuntu.com/ubuntu"
    "archive.ubuntu.com/ubuntu"
    "gb.archive.ubuntu.com/ubuntu"
    "de.archive.ubuntu.com/ubuntu"
    "nl.archive.ubuntu.com/ubuntu"
    "fr.archive.ubuntu.com/ubuntu"
    "se.archive.ubuntu.com/ubuntu"
    "it.archive.ubuntu.com/ubuntu"
    "pl.archive.ubuntu.com/ubuntu"
    "mirrors.edge.kernel.org/ubuntu"
    "us.archive.ubuntu.com/ubuntu"
    "mirrors.mit.edu/ubuntu"
    "au.archive.ubuntu.com/ubuntu"
    "cn.archive.ubuntu.com/ubuntu"
    "jp.archive.ubuntu.com/ubuntu"
    "sg.archive.ubuntu.com/ubuntu"
    "in.archive.ubuntu.com/ubuntu"
)

# ═══════════════════════════════════════════════════════════════════════════
# ФУНКЦИЯ ПРИМЕНЕНИЯ ЗЕРКАЛА
# ═══════════════════════════════════════════════════════════════════════════

apply_mirror() {
    local best_url="$1"
    local best_name="$2"
    
    # Создание резервной копии
    print_section "${ICON_BACKUP} Создание резервной копии"
    
    BACKUP_FILE="/etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S)"
    cp /etc/apt/sources.list "$BACKUP_FILE"
    
    print_success "Резервная копия: ${BLUE}$BACKUP_FILE${RESET}"
    
    # Генерация sources.list
    print_section "📝 Создание нового sources.list"
    
    cat > /etc/apt/sources.list <<EOF
# Сгенерировано скриптом выбора зеркал
# Дата: $(date '+%Y-%m-%d %H:%M:%S')
# Зеркало: $best_name

# Основные репозитории
deb http://$best_url $UBUNTU_VERSION main restricted universe multiverse
deb http://$best_url $UBUNTU_VERSION-updates main restricted universe multiverse
deb http://$best_url $UBUNTU_VERSION-backports main restricted universe multiverse

# Безопасность
deb http://security.ubuntu.com/ubuntu $UBUNTU_VERSION-security main restricted universe multiverse

# Исходные коды (раскомментируйте при необходимости)
# deb-src http://$best_url $UBUNTU_VERSION main restricted universe multiverse
# deb-src http://$best_url $UBUNTU_VERSION-updates main restricted universe multiverse
# deb-src http://$best_url $UBUNTU_VERSION-backports main restricted universe multiverse
# deb-src http://security.ubuntu.com/ubuntu $UBUNTU_VERSION-security main restricted universe multiverse
EOF
    
    print_success "Файл sources.list обновлен"
    echo -e "${DIM}Зеркало: ${CYAN}http://$best_url${RESET}"
    
    # Обновление репозиториев
    print_section "🔄 Обновление репозиториев"
    
    print_info "Выполняется apt update..."
    
    if apt update 2>&1 | grep -q "Err:"; then
        print_error "Ошибка при обновлении репозиториев"
        print_warning "Восстанавливаем резервную копию..."
        cp "$BACKUP_FILE" /etc/apt/sources.list
        apt update > /dev/null 2>&1
        print_info "Резервная копия восстановлена"
        pause_screen
        return 1
    else
        print_success "Репозитории успешно обновлены"
        echo -e "\n${GREEN}${ICON_CHECK}${RESET} ${BOLD}Зеркало успешно применено!${RESET}"
        echo -e "${WHITE}Резервная копия сохранена: ${BLUE}$BACKUP_FILE${RESET}\n"
        pause_screen
        return 0
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# РУЧНОЙ ВЫБОР ЗЕРКАЛА
# ═══════════════════════════════════════════════════════════════════════════

manual_mirror_selection() {
    clear
    print_section "${ICON_MANUAL} Ручной выбор зеркала"
    
    echo -e "${WHITE}Доступные зеркала:${RESET}\n"
    
    for i in "${!MIRROR_NAMES[@]}"; do
        printf "${GRAY}%2d.${RESET} ${BOLD}%-30s${RESET} ${DIM}%s${RESET}\n" \
            "$((i+1))" "${MIRROR_NAMES[$i]}" "${MIRROR_URLS[$i]}"
    done
    
    print_separator
    
    echo -e -n "\n${YELLOW}Введите номер зеркала (1-${#MIRROR_NAMES[@]}) или 0 для отмены:${RESET} "
    read choice
    
    if [[ "$choice" == "0" ]]; then
        print_warning "Отменено пользователем."
        pause_screen
        return 1
    fi
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#MIRROR_NAMES[@]} ]; then
        print_error "Неверный номер зеркала"
        pause_screen
        return 1
    fi
    
    idx=$((choice - 1))
    best_url="${MIRROR_URLS[$idx]}"
    best_name="${MIRROR_NAMES[$idx]}"
    
    print_info "Выбрано: ${BOLD}$best_name${RESET}"
    
    # Проверяем доступность выбранного зеркала
    print_section "🔍 Проверка доступности"
    
    host=$(echo "$best_url" | cut -d'/' -f1)
    
    echo -e -n "${CYAN}Проверка доступности ${BOLD}$host${RESET}... "
    
    if timeout 5 curl -s --head --connect-timeout 3 "http://${best_url}/dists/${UBUNTU_VERSION}/Release" 2>/dev/null | grep -q "200 OK"; then
        echo -e "${GREEN}${ICON_CHECK} Доступно${RESET}"
        
        apply_mirror "$best_url" "$best_name"
    else
        echo -e "${RED}${ICON_CROSS} Недоступно${RESET}"
        print_error "Выбранное зеркало недоступно или не содержит Release файл"
        pause_screen
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# АВТОМАТИЧЕСКИЙ ВЫБОР ЗЕРКАЛА
# ═══════════════════════════════════════════════════════════════════════════

auto_mirror_selection() {
    clear
    
    total=${#MIRROR_NAMES[@]}
    
    print_section "${ICON_CLOCK} Тестирование доступных зеркал"
    echo -e "${WHITE}Проверка ${total} серверов (пинг + наличие Release файлов)...${RESET}"
    echo -e "${WHITE}Это может занять 2-3 минуты...${RESET}\n"
    
    VALID_NAMES=()
    VALID_URLS=()
    VALID_PINGS=()
    
    for i in "${!MIRROR_NAMES[@]}"; do
        name="${MIRROR_NAMES[$i]}"
        url="${MIRROR_URLS[$i]}"
        host=$(echo "$url" | cut -d'/' -f1)
        current=$((i + 1))
        
        printf "${GRAY}[%2d/%2d]${RESET} ${BOLD}%-28s${RESET} " "$current" "$total" "$name"
        
        # Проверка пинга
        ping_time=$(ping -c 3 -W 2 "$host" 2>/dev/null | grep 'avg' | awk -F'/' '{print $5}' 2>/dev/null)
        
        if [ -z "$ping_time" ]; then
            echo -e "${RED}${ICON_CROSS} недоступно${RESET}"
            continue
        fi
        
        # Проверка Release файла
        if timeout 5 curl -s --head --connect-timeout 3 "http://${url}/dists/${UBUNTU_VERSION}/Release" 2>/dev/null | grep -q "200 OK"; then
            printf "${GREEN}${ICON_CHECK}${RESET} ${CYAN}%.1f мс${RESET}\n" "$ping_time"
            
            VALID_NAMES+=("$name")
            VALID_URLS+=("$url")
            VALID_PINGS+=("$ping_time")
        else
            echo -e "${RED}${ICON_CROSS} нет Release${RESET}"
        fi
    done
    
    print_separator
    
    # Проверка наличия доступных зеркал
    if [ ${#VALID_NAMES[@]} -eq 0 ]; then
        print_error "Не найдено доступных зеркал!"
        pause_screen
        return 1
    fi
    
    # Сортировка по пингу
    for ((i=0; i<${#VALID_PINGS[@]}; i++)); do
        for ((j=i+1; j<${#VALID_PINGS[@]}; j++)); do
            if (( $(echo "${VALID_PINGS[$i]} > ${VALID_PINGS[$j]}" | bc -l) )); then
                tmp_name="${VALID_NAMES[$i]}"
                tmp_url="${VALID_URLS[$i]}"
                tmp_ping="${VALID_PINGS[$i]}"
                
                VALID_NAMES[$i]="${VALID_NAMES[$j]}"
                VALID_URLS[$i]="${VALID_URLS[$j]}"
                VALID_PINGS[$i]="${VALID_PINGS[$j]}"
                
                VALID_NAMES[$j]="$tmp_name"
                VALID_URLS[$j]="$tmp_url"
                VALID_PINGS[$j]="$tmp_ping"
            fi
        done
    done
    
    # Вывод результатов
    print_section "📊 Доступные зеркала (топ-15)"
    
    max_display=15
    [ ${#VALID_NAMES[@]} -lt $max_display ] && max_display=${#VALID_NAMES[@]}
    
    for ((i=0; i<$max_display; i++)); do
        ping_color="${GREEN}"
        [ $(echo "${VALID_PINGS[$i]} > 100" | bc -l) -eq 1 ] && ping_color="${YELLOW}"
        [ $(echo "${VALID_PINGS[$i]} > 300" | bc -l) -eq 1 ] && ping_color="${RED}"
        
        printf "${GRAY}%2d.${RESET} ${BOLD}%-28s${RESET} ${ping_color}%8.1f мс${RESET}\n" \
            "$((i+1))" "${VALID_NAMES[$i]}" "${VALID_PINGS[$i]}"
    done
    
    echo ""
    print_separator
    
    echo -e "\n${BOLD}${GREEN}${ICON_TROPHY} ЛУЧШЕЕ ЗЕРКАЛО${RESET}\n"
    echo -e "${CYAN}Название:${RESET} ${BOLD}${WHITE}${VALID_NAMES[0]}${RESET}"
    echo -e "${CYAN}Пинг:${RESET} ${BOLD}${GREEN}${VALID_PINGS[0]} мс${RESET}"
    print_separator
    
    best_url="${VALID_URLS[0]}"
    best_name="${VALID_NAMES[0]}"
    
    echo -e -n "\n${YELLOW}Применить лучшее зеркало? (y/n):${RESET} "
    read choice
    
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        print_warning "Отменено пользователем."
        pause_screen
        return 1
    fi
    
    apply_mirror "$best_url" "$best_name"
}

# ═══════════════════════════════════════════════════════════════════════════
# ГЛАВНОЕ МЕНЮ
# ═══════════════════════════════════════════════════════════════════════════

show_main_menu() {
    clear
    print_header "${ICON_ROCKET} АВТОМАТИЧЕСКИЙ ВЫБОР ЗЕРКАЛА UBUNTU ${ICON_ROCKET}"
    
    echo -e "${BOLD}Выберите действие:${RESET}\n"
    echo -e "  ${CYAN}1.${RESET} ${ICON_AUTO} Автоматический выбор (самое быстрое по пингу)"
    echo -e "  ${CYAN}2.${RESET} ${ICON_MANUAL} Ручной выбор зеркала (без тестирования)"
    echo -e "  ${CYAN}3.${RESET} ${ICON_BACKUP} Управление резервными копиями"
    echo -e "  ${CYAN}0.${RESET} Выход"
    
    echo -e -n "\n${YELLOW}Ваш выбор:${RESET} "
    read main_choice
    
    case "$main_choice" in
        1)
            auto_mirror_selection
            ;;
        2)
            manual_mirror_selection
            ;;
        3)
            show_backup_menu
            ;;
        0)
            clear
            print_success "До свидания!"
            exit 0
            ;;
        *)
            print_error "Неверный выбор"
            sleep 1
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════
# ИНИЦИАЛИЗАЦИЯ
# ═══════════════════════════════════════════════════════════════════════════

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    clear
    print_header "ТРЕБУЮТСЯ ПРАВА ROOT"
    print_error "Пожалуйста, запустите скрипт с правами root:"
    echo -e "  ${YELLOW}sudo $0${RESET}\n"
    exit 1
fi

# Проверка зависимостей (выполняется один раз)
clear
print_section "${ICON_GEAR} Проверка системных зависимостей"

REQUIRED_TOOLS=("ping" "curl" "bc" "lsb_release" "awk" "grep")
MISSING_TOOLS=()
PACKAGES_TO_INSTALL=()

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        print_error "$tool не найдена"
        MISSING_TOOLS+=("$tool")
        case "$tool" in
            "ping")
                PACKAGES_TO_INSTALL+=("iputils-ping")
                ;;
            "curl")
                PACKAGES_TO_INSTALL+=("curl")
                ;;
            "bc")
                PACKAGES_TO_INSTALL+=("bc")
                ;;
            "lsb_release")
                PACKAGES_TO_INSTALL+=("lsb-release")
                ;;
        esac
    else
        print_success "$tool"
    fi
done

if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    echo ""
    print_warning "Необходимо установить: ${BOLD}${PACKAGES_TO_INSTALL[*]}${RESET}"
    echo -e -n "${YELLOW}Установить сейчас? (y/n):${RESET} "
    read install_confirm
    
    if [[ "$install_confirm" =~ ^[Yy]$ ]]; then
        print_info "Установка зависимостей..."
        apt update -qq
        
        for package in "${PACKAGES_TO_INSTALL[@]}"; do
            echo -e "${CYAN}→${RESET} Установка ${BOLD}$package${RESET}..."
            apt install -y "$package" > /dev/null 2>&1
        done
        
        print_success "Все зависимости установлены"
        sleep 2
    else
        print_error "Отменено. Установите необходимые пакеты вручную:"
        echo -e "  ${YELLOW}sudo apt install ${PACKAGES_TO_INSTALL[*]}${RESET}\n"
        exit 1
    fi
fi

# Определение версии Ubuntu (один раз)
UBUNTU_VERSION=$(lsb_release -cs 2>/dev/null || echo "jammy")
UBUNTU_NUMERIC=$(lsb_release -rs 2>/dev/null || echo "22.04")

# ═══════════════════════════════════════════════════════════════════════════
# ГЛАВНЫЙ ЦИКЛ
# ═══════════════════════════════════════════════════════════════════════════

while true; do
    show_main_menu
done
