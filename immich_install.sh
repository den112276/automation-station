#!/bin/bash

# Скрипт с меню для управления Immich (установка/удаление)
# Решает проблему с volumes и другими распространёнными ошибками

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
LIGHT_CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Основные параметры
IMMICH_DIR="/opt/immich"
DOCKER_COMPOSE_URL="https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml"

# Проверка прав
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Ошибка: Скрипт должен запускаться с правами root (sudo)${NC}"
    exit 1
fi

# Установка Docker если нужно
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${CYAN}Установка Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        usermod -aG docker $SUDO_USER
        systemctl enable --now docker
        echo -e "${GREEN}Docker установлен!${NC}"
        echo -e "${YELLOW}Выйдите и зайдите снова для применения изменений групп.${NC}"
        exit 0
    fi
}

# Установка Docker Compose если нужно
install_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${CYAN}Установка Docker Compose...${NC}"
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
        curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
        echo -e "${GREEN}Docker Compose установлен!${NC}"
    fi
}

# Создаем рабочий docker-compose.yml
create_docker_compose() {
    cat > "${IMMICH_DIR}/docker-compose.yml" << 'EOL'
name: immich

services:
  immich-server:
    container_name: immich_server
    image: ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-release}
    # extends:
    #   file: hwaccel.transcoding.yml
    #   service: cpu # set to one of [nvenc, quicksync, rkmpp, vaapi, vaapi-wsl] for accelerated transcoding
    volumes:
      # Do not edit the next line. If you want to change the media storage location on your system, edit the value of UPLOAD_LOCATION in the .env file
      - ${UPLOAD_LOCATION}:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env
    ports:
      - '2283:2283'
    depends_on:
      - redis
      - database
    restart: always
    healthcheck:
      disable: false

  immich-machine-learning:
    container_name: immich_machine_learning
    # For hardware acceleration, add one of -[armnn, cuda, rocm, openvino, rknn] to the image tag.
    # Example tag: ${IMMICH_VERSION:-release}-cuda
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION:-release}
    # extends: # uncomment this section for hardware acceleration - see https://immich.app/docs/features/ml-hardware-acceleration
    #   file: hwaccel.ml.yml
    #   service: cpu # set to one of [armnn, cuda, rocm, openvino, openvino-wsl, rknn] for accelerated inference - use the `-wsl` version for WSL2 where applicable
    volumes:
      - model-cache:/cache
    env_file:
      - .env
    restart: always
    healthcheck:
      disable: false

  redis:
    container_name: immich_redis
    image: docker.io/valkey/valkey:8-bookworm@sha256:fec42f399876eb6faf9e008570597741c87ff7662a54185593e74b09ce83d177
    healthcheck:
      test: redis-cli ping || exit 1
    restart: always

  database:
    container_name: immich_postgres
    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_DB: ${DB_DATABASE_NAME}
      POSTGRES_INITDB_ARGS: '--data-checksums'
      # Uncomment the DB_STORAGE_TYPE: 'HDD' var if your database isn't stored on SSDs
      # DB_STORAGE_TYPE: 'HDD'
    volumes:
      # Do not edit the next line. If you want to change the database storage location on your system, edit the value of DB_DATA_LOCATION in the .env file
      - ${DB_DATA_LOCATION}:/var/lib/postgresql/data
    restart: always

volumes:
  model-cache:    
EOL
}

# Создаем .env файл
create_env_file() {
    JWT_SECRET=$(openssl rand -base64 128 | tr -d '\n')
    cat > "${IMMICH_DIR}/.env" << EOL
# You can find documentation for all the supported env variables at https://immich.app/docs/install/environment-variables

# The location where your uploaded files are stored
UPLOAD_LOCATION=./library

# The location where your database files are stored. Network shares are not supported for the database
DB_DATA_LOCATION=./postgres

# To set a timezone, uncomment the next line and change Etc/UTC to a TZ identifier from this list: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List
# TZ=Etc/UTC

# The Immich version to use. You can pin this to a specific version like "v1.71.0"
IMMICH_VERSION=release

# Connection secret for postgres. You should change it to a random password
# Please use only the characters 'A-Za-z0-9', without special characters or spaces
DB_PASSWORD=postgres

# The values below this line do not need to be changed
###################################################################################
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
    
EOL
}

# Установка Immich
install_immich() {
    echo -e "${MAGENTA}Начало установки Immich...${NC}"
    
    # Установка зависимостей
    install_docker
    install_compose
    
    # Создаем директорию
    echo -e "${CYAN}Создаем рабочую директорию...${NC}"
    mkdir -p "${IMMICH_DIR}"
    cd "${IMMICH_DIR}"
    
    # Создаем конфигурационные файлы
    echo -e "${CYAN}Создаем конфигурационные файлы...${NC}"
    create_docker_compose
    create_env_file
    
    # Создаем директорию для загрузок
    mkdir -p upload
    
    # Запускаем Immich
    echo -e "${CYAN}Запускаем Immich...${NC}"
    docker-compose up -d
    
    # Проверяем
    echo -e "${CYAN}Проверяем работу сервисов...${NC}"
    docker-compose ps
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Установка завершена успешно!${NC}"
    echo -e "Immich доступен по адресу: ${YELLOW}http://localhost:2283${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# Удаление Immich
uninstall_immich() {
    echo -e "${MAGENTA}Начало удаления Immich...${NC}"
    
    if [ -d "${IMMICH_DIR}" ]; then
        cd "${IMMICH_DIR}"
        
        # Останавливаем и удаляем контейнеры
        if [ -f "docker-compose.yml" ]; then
            echo -e "${CYAN}Останавливаем и удаляем контейнеры...${NC}"
            docker-compose down
        fi
        
        # Удаляем директорию
        echo -e "${CYAN}Удаляем директорию Immich...${NC}"
        cd ..
        rm -rf "${IMMICH_DIR}"
    else
        echo -e "${RED}Директория Immich не найдена. Возможно, Immich не установлен.${NC}"
    fi

    # Очистка неиспользуемых ресурсов Docker
    echo -e "${CYAN}Очищаем неиспользуемые ресурсы Docker...${NC}"
    docker system prune -af --volumes

    # Удаляем именованный том, если он остался
    if docker volume ls -q | grep -q "^immich_model-cache$"; then
        echo -e "${CYAN}Удаляем именованный том immich_model-cache...${NC}"
        docker volume rm immich_model-cache
    fi

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Удаление завершено успешно!${NC}"
    echo -e "${GREEN}========================================${NC}"
}
# Показываем меню
show_menu() {
    clear
    echo -e "${LIGHT_CYAN}========================================${NC}"
    echo -e "${YELLOW} Меню управления Immich${NC}"
    echo -e "${LIGHT_CYAN}========================================${NC}"
    echo -e "${GREEN}1. Установить Immich${NC}"
    echo -e "${RED}2. Удалить Immich${NC}"
    echo -e "${MAGENTA}3. Выход${NC}"
    echo -e "${LIGHT_CYAN}========================================${NC}"
    echo -n "Выберите пункт меню (1-3): "
}

# Основной цикл
while true; do
    show_menu
    read choice
    case $choice in
        1)
            install_immich
            read -p "Нажмите Enter для продолжения..."
            ;;
        2)
            uninstall_immich
            read -p "Нажмите Enter для продолжения..."
            ;;
        3)
            echo -e "${MAGENTA}Выход...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор. Попробуйте снова.${NC}"
            read -p "Нажмите Enter для продолжения..."
            ;;
    esac
done