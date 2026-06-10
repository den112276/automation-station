#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Файл для сохранения списка найденных окружений
VENVS_DB="$HOME/.venvs_manager_db.txt"

# Определяем, запущен ли скрипт как source или напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_MODE="direct"
else
    SCRIPT_MODE="sourced"
fi

# Функция для очистки экрана
clear_screen() {
    clear
}

# Функция для паузы и очистки
pause_and_clear() {
    echo -e "\n${CYAN}🔹 Нажмите Enter для продолжения...${NC}"
    read
    clear_screen
}

# Функция для проверки установки Python
check_python() {
    echo -e "${CYAN}🔍 Проверка системных требований...${NC}"
    
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}❌ Python3 не установлен!${NC}"
        return 1
    fi
    
    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    echo -e "${GREEN}✅ Python $PYTHON_VERSION${NC}"
    
    if ! python3 -c "import venv" &> /dev/null; then
        echo -e "${RED}❌ Модуль venv не установлен!${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Модуль venv доступен${NC}"
    return 0
}

# Функция для проверки, является ли директория виртуальным окружением
is_valid_venv() {
    local venv_path="$1"
    
    if [[ ! -d "$venv_path" ]]; then
        return 1
    fi
    
    if [[ -f "$venv_path/bin/activate" ]] || [[ -f "$venv_path/Scripts/activate" ]]; then
        if [[ -f "$venv_path/bin/python" ]] || [[ -f "$venv_path/Scripts/python.exe" ]]; then
            return 0
        fi
    fi
    
    return 1
}

# Функция для активации окружения
activate_venv() {
    local venv_path="$1"
    
    if [[ ! -d "$venv_path" ]]; then
        echo -e "${RED}❌ Окружение не найдено: $venv_path${NC}"
        return 1
    fi
    
    if [[ -f "$venv_path/bin/activate" ]]; then
        source "$venv_path/bin/activate"
        echo -e "${GREEN}✅ Активировано окружение: $(basename "$venv_path")${NC}"
        echo -e "${CYAN}📌 Текущий Python: $(which python)${NC}"
        return 0
    elif [[ -f "$venv_path/Scripts/activate" ]]; then
        source "$venv_path/Scripts/activate"
        echo -e "${GREEN}✅ Активировано окружение: $(basename "$venv_path")${NC}"
        return 0
    else
        echo -e "${RED}❌ Файл активации не найден!${NC}"
        return 1
    fi
}

# Функция для получения pip
get_pip() {
    local venv_path="$1"
    
    if [[ -f "$venv_path/bin/pip" ]]; then
        echo "$venv_path/bin/pip"
    elif [[ -f "$venv_path/bin/pip3" ]]; then
        echo "$venv_path/bin/pip3"
    elif [[ -f "$venv_path/Scripts/pip.exe" ]]; then
        echo "$venv_path/Scripts/pip.exe"
    else
        echo ""
    fi
}

# Функция для очистки и дедупликации базы данных
cleanup_and_deduplicate() {
    if [[ ! -f "$VENVS_DB" ]] || [[ ! -s "$VENVS_DB" ]]; then
        return 0
    fi
    
    local temp_file=$(mktemp)
    
    while IFS= read -r venv_path; do
        if is_valid_venv "$venv_path"; then
            echo "$venv_path" >> "$temp_file"
        fi
    done < "$VENVS_DB"
    
    sort -u "$temp_file" > "$VENVS_DB"
    rm "$temp_file"
}

# Функция для поиска всех виртуальных окружений в системе
scan_all_venvs() {
    echo -e "\n${YELLOW}🔍 Поиск всех виртуальных окружений...${NC}"
    echo -e "${CYAN}Это может занять некоторое время...${NC}"
    
    local temp_file=$(mktemp)
    
    if [[ -d "$HOME" ]]; then
        while IFS= read -r activate_file; do
            local activate_dir=$(dirname "$activate_file")
            local venv_path=$(dirname "$activate_dir")
            
            if is_valid_venv "$venv_path"; then
                # Исключаем вложенные окружения
                local parent_dir=$(dirname "$venv_path")
                if [[ ! -f "$parent_dir/bin/activate" ]]; then
                    echo "$venv_path" >> "$temp_file"
                fi
            fi
        done < <(find "$HOME" -maxdepth 5 -type f -name "activate" 2>/dev/null | grep -v "lib/python" | grep -v "lib64/python")
    fi
    
    sort -u "$temp_file" > "$VENVS_DB"
    local found=$(wc -l < "$VENVS_DB")
    rm "$temp_file"
    
    echo -e "${GREEN}✅ Найдено $found виртуальных окружений${NC}"
    cleanup_and_deduplicate
}

# Функция для создания виртуального окружения
create_venv() {
    clear_screen
    echo -e "\n${MAGENTA}🔨 СОЗДАНИЕ НОВОГО ВИРТУАЛЬНОГО ОКРУЖЕНИЯ${NC}"
    echo "========================================="
    echo -e "${CYAN}0. 🔙 Назад в главное меню${NC}"
    echo "========================================="
    
    echo -e "${CYAN}Где создать окружение?${NC}"
    echo "1. В стандартной папке (~/.venvs/)"
    echo "2. В текущей директории"
    echo "3. В указанной директории"
    read -p "Выберите (0-3): " location_choice
    
    case $location_choice in
        0)
            return 0
            ;;
        1)
            local base_dir="$HOME/.venvs"
            mkdir -p "$base_dir"
            ;;
        2)
            local base_dir="$(pwd)"
            ;;
        3)
            read -p "Введите путь: " base_dir
            base_dir=$(realpath "$base_dir" 2>/dev/null || echo "$base_dir")
            if [[ ! -d "$base_dir" ]]; then
                echo -e "${YELLOW}Директория не существует. Создать? (y/N): ${NC}"
                read create_dir
                [[ "$create_dir" == "y" || "$create_dir" == "Y" ]] && mkdir -p "$base_dir" || return 0
            fi
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор!${NC}"
            sleep 1
            return 0
            ;;
    esac
    
    read -p "Введите имя окружения (Enter для отмены): " venv_name
    [[ -z "$venv_name" ]] && echo -e "${YELLOW}Операция отменена${NC}" && sleep 1 && return 0
    
    VENV_PATH="$base_dir/$venv_name"
    
    if [[ -d "$VENV_PATH" ]]; then
        echo -e "${RED}❌ Директория '$VENV_PATH' уже существует!${NC}"
        sleep 1
        return 0
    fi
    
    read -p "Использовать системные пакеты? (y/N): " use_system
    
    echo -e "\n${YELLOW}⏳ Создание окружения '$venv_name'...${NC}"
    
    if [[ "$use_system" == "y" || "$use_system" == "Y" ]]; then
        python3 -m venv --system-site-packages "$VENV_PATH"
    else
        python3 -m venv "$VENV_PATH"
    fi
    
    if [[ $? -eq 0 ]] && is_valid_venv "$VENV_PATH"; then
        echo -e "${GREEN}✅ Окружение успешно создано!${NC}"
        echo "$VENV_PATH" >> "$VENVS_DB"
        cleanup_and_deduplicate
        
        # Спрашиваем, активировать ли сразу
        echo -e "\n${CYAN}Активировать окружение сейчас? (y/N): ${NC}"
        read activate_now
        if [[ "$activate_now" == "y" || "$activate_now" == "Y" ]]; then
            if [[ "$SCRIPT_MODE" == "sourced" ]]; then
                activate_venv "$VENV_PATH"
                echo -e "${YELLOW}💡 Для деактивации выполните: deactivate${NC}"
            else
                echo -e "${YELLOW}⚠️ Для активации перезапустите скрипт с source:${NC}"
                echo -e "  ${GREEN}source $(basename "${BASH_SOURCE[0]}")${NC}"
            fi
        fi
        
        # Спрашиваем про установку зависимостей
        echo -e "\n${CYAN}📦 Установить зависимости из requirements.txt? (y/N): ${NC}"
        read install_req
        if [[ "$install_req" == "y" || "$install_req" == "Y" ]]; then
            if [[ -f "requirements.txt" ]]; then
                local pip_cmd=$(get_pip "$VENV_PATH")
                if [[ -n "$pip_cmd" ]]; then
                    $pip_cmd install -r requirements.txt
                    echo -e "${GREEN}✅ Зависимости установлены!${NC}"
                fi
            else
                echo -e "${YELLOW}⚠️ Файл requirements.txt не найден в текущей папке${NC}"
            fi
        fi
    else
        echo -e "${RED}❌ Ошибка при создании окружения!${NC}"
        sleep 1
        return 0
    fi
}

# Функция для удаления виртуального окружения
delete_venv() {
    clear_screen
    echo -e "\n${MAGENTA}🗑️  УДАЛЕНИЕ ВИРТУАЛЬНОГО ОКРУЖЕНИЯ${NC}"
    echo "========================================="
    echo -e "${CYAN}0. 🔙 Назад в главное меню${NC}"
    echo "========================================="
    
    # Показываем список окружений
    list_venvs
    
    local venvs=()
    while IFS= read -r venv_path; do
        venvs+=("$venv_path")
    done < <(cat "$VENVS_DB" 2>/dev/null)
    
    if [[ ${#venvs[@]} -eq 0 ]]; then
        return 0
    fi
    
    read -p "Введите номер окружения для удаления (0 для выхода): " choice
    
    if [[ "$choice" == "0" ]]; then
        echo -e "${YELLOW}Операция отменена${NC}"
        sleep 1
        return 0
    fi
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#venvs[@]} ]]; then
        echo -e "${RED}❌ Неверный выбор!${NC}"
        sleep 1
        return 0
    fi
    
    venv_path="${venvs[$((choice-1))]}"
    venv_name=$(basename "$venv_path")
    
    # Проверяем, не активировано ли это окружение
    if [[ "$VIRTUAL_ENV" == "$venv_path" ]]; then
        echo -e "${RED}⚠️ Это окружение сейчас активировано!${NC}"
        read -p "Деактивировать и удалить? (y/N): " deactivate_confirm
        if [[ "$deactivate_confirm" == "y" || "$deactivate_confirm" == "Y" ]]; then
            deactivate 2>/dev/null
            echo -e "${GREEN}✅ Окружение деактивировано${NC}"
        else
            echo -e "${YELLOW}Удаление отменено${NC}"
            sleep 1
            return 0
        fi
    fi
    
    read -p "⚠️  Удалить '$venv_name'? (y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Удаление отменено${NC}"
        sleep 1
        return 0
    fi
    
    rm -rf "$venv_path"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Окружение удалено!${NC}"
        grep -v "^${venv_path}$" "$VENVS_DB" > "${VENVS_DB}.tmp"
        mv "${VENVS_DB}.tmp" "$VENVS_DB"
        cleanup_and_deduplicate
        sleep 1
    else
        echo -e "${RED}❌ Ошибка при удалении!${NC}"
        sleep 1
        return 0
    fi
}

# Функция для отображения списка окружений
list_venvs() {
    cleanup_and_deduplicate
    
    local venvs=()
    while IFS= read -r venv_path; do
        if is_valid_venv "$venv_path"; then
            venvs+=("$venv_path")
        fi
    done < <(cat "$VENVS_DB" 2>/dev/null)
    
    if [[ ${#venvs[@]} -eq 0 ]]; then
        echo -e "\n${YELLOW}📭 Нет доступных виртуальных окружений${NC}"
        echo -e "${CYAN}💡 Создайте новое через пункт 1${NC}"
        return 0
    fi
    
    echo -e "\n"
    for i in "${!venvs[@]}"; do
        venv_path="${venvs[$i]}"
        venv_name=$(basename "$venv_path")
        size=$(du -sh "$venv_path" 2>/dev/null | awk '{print $1}')
        
        if [[ -f "$venv_path/bin/python" ]]; then
            python_ver=$("$venv_path/bin/python" --version 2>&1 | awk '{print $2}')
        else
            python_ver="Неизвестно"
        fi
        
        # Отмечаем активное окружение
        active_mark=""
        if [[ "$VIRTUAL_ENV" == "$venv_path" ]]; then
            active_mark=" ${GREEN}⭐ АКТИВНО${NC}"
        fi
        
        if [[ "$venv_name" == .* ]]; then
            echo -e "${YELLOW}$((i+1)). 🔒 $venv_name (скрытое)$active_mark${NC}"
        else
            echo -e "${GREEN}$((i+1)). 📁 $venv_name$active_mark${NC}"
        fi
        echo -e "   📍 Путь: $venv_path"
        echo -e "   🐍 Python: $python_ver"
        echo -e "   💾 Размер: ${size:-0B}"
        echo "   ----------------------------------------"
    done
    
    echo -e "${CYAN}📊 Всего окружений: ${#venvs[@]}${NC}"
    
    if [[ -n "$VIRTUAL_ENV" ]]; then
        echo -e "${GREEN}⭐ Текущее активное окружение: $(basename "$VIRTUAL_ENV")${NC}"
        echo -e "${YELLOW}🔧 Для деактивации выполните: deactivate${NC}"
    fi
}

# Функция для активации окружения
activate_environment() {
    clear_screen
    echo -e "\n${CYAN}🚀 АКТИВАЦИЯ ВИРТУАЛЬНОГО ОКРУЖЕНИЯ${NC}"
    echo "========================================="
    echo -e "${CYAN}0. 🔙 Назад в главное меню${NC}"
    echo "========================================="
    
    if [[ "$SCRIPT_MODE" != "sourced" ]]; then
        echo -e "${RED}❌ Для активации нужно запустить скрипт командой:${NC}"
        echo -e "${GREEN}  source $(basename "${BASH_SOURCE[0]}")${NC}"
        echo -e "${YELLOW}Или:${NC} ${GREEN}. $(basename "${BASH_SOURCE[0]}")${NC}"
        pause_and_clear
        return 0
    fi
    
    list_venvs
    
    local venvs=()
    while IFS= read -r venv_path; do
        venvs+=("$venv_path")
    done < <(cat "$VENVS_DB" 2>/dev/null)
    
    if [[ ${#venvs[@]} -eq 0 ]]; then
        echo -e "${RED}❌ Нет доступных окружений!${NC}"
        pause_and_clear
        return 0
    fi
    
    read -p "Введите номер окружения для активации (0 для выхода): " choice
    
    if [[ "$choice" == "0" ]]; then
        echo -e "${YELLOW}Операция отменена${NC}"
        sleep 1
        return 0
    fi
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#venvs[@]} ]]; then
        echo -e "${RED}❌ Неверный выбор!${NC}"
        sleep 1
        return 0
    fi
    
    venv_path="${venvs[$((choice-1))]}"
    
    if activate_venv "$venv_path"; then
        echo -e "\n${GREEN}✨ Окружение активировано!${NC}"
        echo -e "${YELLOW}🔧 Для деактивации выполните: deactivate${NC}"
        return 0
    fi
}

# Функция для установки зависимостей
install_requirements() {
    clear_screen
    echo -e "\n${MAGENTA}📦 УСТАНОВКА ЗАВИСИМОСТЕЙ ИЗ REQUIREMENTS.TXT${NC}"
    echo "========================================="
    echo -e "${CYAN}0. 🔙 Назад в главное меню${NC}"
    echo "========================================="
    
    # Выбор окружения
    local venv_path=""
    local pip_cmd=""
    
    # Если есть активное окружение, предлагаем использовать его
    if [[ -n "$VIRTUAL_ENV" ]]; then
        echo -e "${GREEN}⭐ Активное окружение: $(basename "$VIRTUAL_ENV")${NC}"
        read -p "Использовать активное окружение? (Y/n/0-выход): " use_active
        if [[ "$use_active" == "0" ]]; then
            return 0
        fi
        if [[ "$use_active" != "n" && "$use_active" != "N" ]]; then
            venv_path="$VIRTUAL_ENV"
            pip_cmd=$(get_pip "$venv_path")
        fi
    fi
    
    # Если не используем активное или его нет, показываем список
    if [[ -z "$pip_cmd" ]]; then
        list_venvs
        
        local venvs=()
        while IFS= read -r venv_path_item; do
            venvs+=("$venv_path_item")
        done < <(cat "$VENVS_DB" 2>/dev/null)
        
        if [[ ${#venvs[@]} -eq 0 ]]; then
            echo -e "${RED}❌ Нет доступных окружений!${NC}"
            sleep 1
            return 0
        fi
        
        read -p "Введите номер окружения (0 для выхода): " choice
        
        if [[ "$choice" == "0" ]]; then
            return 0
        fi
        
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#venvs[@]} ]]; then
            echo -e "${RED}❌ Неверный выбор!${NC}"
            sleep 1
            return 0
        fi
        
        venv_path="${venvs[$((choice-1))]}"
        pip_cmd=$(get_pip "$venv_path")
    fi
    
    if [[ -z "$pip_cmd" ]]; then
        echo -e "${RED}❌ Pip не найден в окружении!${NC}"
        sleep 1
        return 0
    fi
    
    if [[ -f "requirements.txt" ]]; then
        echo -e "\n${YELLOW}Установка из requirements.txt...${NC}"
        $pip_cmd install -r requirements.txt
        echo -e "${GREEN}✅ Готово!${NC}"
    else
        echo -e "${RED}❌ Файл requirements.txt не найден в текущей папке!${NC}"
        echo -e "${CYAN}Текущая папка: $(pwd)${NC}"
    fi
    sleep 2
}

# Функция для управления пакетами
manage_packages() {
    while true; do
        clear_screen
        echo -e "\n${MAGENTA}📦 УПРАВЛЕНИЕ ПАКЕТАМИ${NC}"
        echo "========================================="
        echo -e "${CYAN}0. 🔙 Назад в главное меню${NC}"
        echo "========================================="
        
        local venv_path=""
        local pip_cmd=""
        
        # Если есть активное окружение, предлагаем использовать его
        if [[ -n "$VIRTUAL_ENV" ]]; then
            echo -e "${GREEN}⭐ Активное окружение: $(basename "$VIRTUAL_ENV")${NC}"
            read -p "Использовать активное окружение? (Y/n/0-выход): " use_active
            if [[ "$use_active" == "0" ]]; then
                return 0
            fi
            if [[ "$use_active" != "n" && "$use_active" != "N" ]]; then
                venv_path="$VIRTUAL_ENV"
                pip_cmd=$(get_pip "$venv_path")
            fi
        fi
        
        # Если не используем активное или его нет, показываем список
        if [[ -z "$pip_cmd" ]]; then
            list_venvs
            
            local venvs=()
            while IFS= read -r venv_path_item; do
                venvs+=("$venv_path_item")
            done < <(cat "$VENVS_DB" 2>/dev/null)
            
            if [[ ${#venvs[@]} -eq 0 ]]; then
                echo -e "${RED}❌ Нет доступных окружений!${NC}"
                pause_and_clear
                return 0
            fi
            
            echo -e "\n${CYAN}0. 🔙 Назад в главное меню${NC}"
            read -p "Введите номер окружения (0 для выхода): " choice
            
            if [[ "$choice" == "0" ]]; then
                return 0
            fi
            
            if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#venvs[@]} ]]; then
                echo -e "${RED}❌ Неверный выбор!${NC}"
                pause_and_clear
                continue
            fi
            
            venv_path="${venvs[$((choice-1))]}"
            pip_cmd=$(get_pip "$venv_path")
        fi
        
        if [[ -z "$pip_cmd" ]]; then
            echo -e "${RED}❌ Pip не найден в окружении!${NC}"
            pause_and_clear
            continue
        fi
        
        # Меню управления пакетами
        while true; do
            clear_screen
            echo -e "\n${CYAN}📦 УПРАВЛЕНИЕ ПАКЕТАМИ${NC}"
            echo "========================================="
            echo -e "${GREEN}Окружение: $(basename "$venv_path")${NC}"
            echo "========================================="
            echo "1. 📋 Список установленных пакетов"
            echo "2. 📦 Установить пакет"
            echo "3. 🗑️  Удалить пакет"
            echo "4. 📝 Обновить пакет"
            echo "5. ⬆️  Обновить все пакеты"
            echo "6. 📄 Установить из requirements.txt"
            echo "7. 💾 Создать requirements.txt"
            echo "8. 🔙 Назад к списку окружений"
            echo "9. 🏠 Выход в главное меню"
            echo "========================================="
            
            read -p "Выберите действие (1-9): " pkg_choice
            
            case $pkg_choice in
                1)
                    echo -e "\n${CYAN}📋 Установленные пакеты:${NC}"
                    $pip_cmd list
                    pause_and_clear
                    ;;
                2)
                    read -p "Введите имя пакета (Enter для отмены): " package
                    if [[ -n "$package" ]]; then
                        echo -e "\n${YELLOW}Установка $package...${NC}"
                        $pip_cmd install "$package"
                        pause_and_clear
                    fi
                    ;;
                3)
                    read -p "Введите имя пакета (Enter для отмены): " package
                    if [[ -n "$package" ]]; then
                        echo -e "\n${YELLOW}Удаление $package...${NC}"
                        $pip_cmd uninstall "$package" -y
                        pause_and_clear
                    fi
                    ;;
                4)
                    read -p "Введите имя пакета (Enter для отмены): " package
                    if [[ -n "$package" ]]; then
                        echo -e "\n${YELLOW}Обновление $package...${NC}"
                        $pip_cmd install --upgrade "$package"
                        pause_and_clear
                    fi
                    ;;
                5)
                    echo -e "\n${YELLOW}Обновление всех пакетов...${NC}"
                    $pip_cmd list --outdated --format=freeze | grep -v '^\-e' | cut -d = -f 1 | xargs -n1 $pip_cmd install -U
                    echo -e "${GREEN}✅ Обновление завершено!${NC}"
                    pause_and_clear
                    ;;
                6)
                    if [[ -f "requirements.txt" ]]; then
                        echo -e "\n${YELLOW}Установка из requirements.txt...${NC}"
                        $pip_cmd install -r requirements.txt
                        echo -e "${GREEN}✅ Готово!${NC}"
                    else
                        read -p "Введите путь к requirements.txt (Enter для отмены): " req_file
                        if [[ -n "$req_file" && -f "$req_file" ]]; then
                            $pip_cmd install -r "$req_file"
                            echo -e "${GREEN}✅ Готово!${NC}"
                        else
                            echo -e "${RED}❌ Файл не найден или отмена!${NC}"
                        fi
                    fi
                    pause_and_clear
                    ;;
                7)
                    read -p "Имя файла (по умолчанию requirements.txt, Enter для отмены): " req_file
                    if [[ -n "$req_file" ]]; then
                        $pip_cmd freeze > "$req_file"
                        echo -e "${GREEN}✅ Создан $req_file${NC}"
                    else
                        $pip_cmd freeze > "requirements.txt"
                        echo -e "${GREEN}✅ Создан requirements.txt${NC}"
                    fi
                    pause_and_clear
                    ;;
                8)
                    # Возвращаемся к выбору окружения
                    break
                    ;;
                9)
                    # Выход в главное меню
                    return 0
                    ;;
                *)
                    echo -e "${RED}❌ Неверный выбор!${NC}"
                    pause_and_clear
                    ;;
            esac
        done
    done
}

# Функция для отображения системной информации
system_info() {
    clear_screen
    echo -e "\n${CYAN}ℹ️  СИСТЕМНАЯ ИНФОРМАЦИЯ${NC}"
    echo "========================================="
    echo -e "${CYAN}0. 🔙 Назад в главное меню${NC}"
    echo "========================================="
    
    echo -e "${GREEN}🐍 Python:${NC} $(python3 --version 2>&1)"
    echo -e "${GREEN}📂 Путь к Python:${NC} $(which python3)"
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo -e "${GREEN}💻 ОС:${NC} $NAME $VERSION"
    fi
    
    echo -e "${GREEN}🏠 Домашняя директория:${NC} $HOME"
    echo -e "${GREEN}💾 Текущая директория:${NC} $(pwd)"
    
    cleanup_and_deduplicate
    local valid_count=$(cat "$VENVS_DB" 2>/dev/null | wc -l)
    echo -e "${GREEN}📦 Всего окружений в базе:${NC} $valid_count"
    
    if [[ -n "$VIRTUAL_ENV" ]]; then
        echo -e "${GREEN}⭐ Активное окружение:${NC} $(basename "$VIRTUAL_ENV")"
        echo -e "${GREEN}   Путь:${NC} $VIRTUAL_ENV"
    fi
    
    if [[ -f "requirements.txt" ]]; then
        local req_count=$(wc -l < "requirements.txt")
        echo -e "${GREEN}📄 requirements.txt найден ($req_count записей)${NC}"
    fi
    
    echo -e "\n${CYAN}💡 Для активации окружения запустите скрипт как:${NC}"
    echo -e "  ${GREEN}source $(basename "${BASH_SOURCE[0]}")${NC}"
    echo "========================================="
    
    read -p "Нажмите Enter для возврата в главное меню..."
}

# Функция отображения меню
show_menu() {
    clear_screen
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${MAGENTA}🐍 МЕНЕДЖЕР ВИРТУАЛЬНЫХ ОКРУЖЕНИЙ PYTHON${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${GREEN}1.${NC} 📦 Создать новое виртуальное окружение"
    echo -e "${GREEN}2.${NC} 🗑️  Удалить виртуальное окружение"
    echo -e "${GREEN}3.${NC} 📋 Просмотр всех окружений"
    echo -e "${GREEN}4.${NC} 🚀 Активировать окружение"
    echo -e "${GREEN}5.${NC} 📦 Управление пакетами (pip)"
    echo -e "${GREEN}6.${NC} 📄 Установить из requirements.txt"
    echo -e "${GREEN}7.${NC} ℹ️  Информация о системе"
    echo -e "${GREEN}8.${NC} 🚪 Выход"
    echo -e "${BLUE}==================================================${NC}"
    
    if [[ "$SCRIPT_MODE" == "sourced" ]]; then
        echo -e "${GREEN}✨ Режим: АКТИВАЦИЯ ДОСТУПНА${NC}"
    else
        echo -e "${YELLOW}⚠️  Режим: только просмотр (для активации используйте 'source')${NC}"
    fi
    
    if [[ -n "$VIRTUAL_ENV" ]]; then
        echo -e "${GREEN}⭐ Активно: $(basename "$VIRTUAL_ENV")${NC}"
    fi
    echo -e "${BLUE}==================================================${NC}"
}

# Главная функция
main() {
    if [[ "$SCRIPT_MODE" == "direct" ]]; then
        echo -e "${YELLOW}⚠️  ВНИМАНИЕ: Вы запустили скрипт напрямую${NC}"
        echo -e "${CYAN}Для возможности активации окружений используйте:${NC}"
        echo -e "  ${GREEN}source $(basename "${BASH_SOURCE[0]}")${NC}"
        echo -e "${CYAN}или${NC}"
        echo -e "  ${GREEN}. $(basename "${BASH_SOURCE[0]}")${NC}"
        echo -e "\n${YELLOW}Продолжить в режиме только для просмотра? (y/N): ${NC}"
        read continue_anyway
        if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
            echo -e "${RED}Выход...${NC}"
            return 1
        fi
    fi
    
    if ! check_python; then
        echo -e "\n${RED}❌ Проверка требований не пройдена. Выход...${NC}"
        pause_and_clear
        return 1
    fi
    
    # Первоначальный поиск, если база пуста
    if [[ ! -f "$VENVS_DB" ]] || [[ ! -s "$VENVS_DB" ]]; then
        scan_all_venvs
        pause_and_clear
    else
        cleanup_and_deduplicate
    fi
    
    while true; do
        show_menu
        read -p "👉 Выберите действие (1-8): " choice
        
        case $choice in
            1) 
                create_venv
                ;;
            2) 
                delete_venv
                ;;
            3) 
                clear_screen
                echo -e "\n${CYAN}📋 ВСЕ ВИРТУАЛЬНЫЕ ОКРУЖЕНИЯ${NC}"
                echo "========================================="
                list_venvs
                echo -e "\n${CYAN}0. 🔙 Назад в главное меню${NC}"
                read -p "Нажмите Enter для возврата..."
                ;;
            4) 
                activate_environment
                if [[ "$SCRIPT_MODE" == "sourced" ]] && [[ $? -eq 0 ]]; then
                    return 0
                fi
                ;;
            5) 
                manage_packages
                ;;
            6) 
                install_requirements
                ;;
            7) 
                system_info
                ;;
            8) 
                echo -e "\n${GREEN}👋 До свидания!${NC}"
                return 0
                ;;
            *)
                echo -e "\n${RED}❌ Неверный выбор!${NC}"
                sleep 1
                ;;
        esac
    done
}

# Запуск скрипта
main