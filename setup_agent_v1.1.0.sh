#author: Long Le
#!/bin/bash

# setup_agent.sh - Edge Controller Installation Script (Docker Compose + Auto-Install Docker)
# Usage: sudo bash setup_agent.sh

set -e

# --- Configuration & Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
LIGHTGREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Check for root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${RESET}"
   exit 1
fi

# Detect Package Manager
if command -v apt-get &> /dev/null; then
    PACKAGE_MANAGER="apt-get"
elif command -v yum &> /dev/null; then
    PACKAGE_MANAGER="yum"
elif command -v dnf &> /dev/null; then
    PACKAGE_MANAGER="dnf"
elif command -v pacman &> /dev/null; then
    PACKAGE_MANAGER="pacman"
elif command -v apk &> /dev/null; then
    PACKAGE_MANAGER="apk"
else
    echo -e "${RED}Unsupported package manager.${RESET}"
    exit 1
fi

# Detect OS Distribution and Codename
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_DISTRO=$ID
    OS_CODENAME=$VERSION_CODENAME
    if [ -z "$OS_CODENAME" ]; then
        OS_CODENAME=$(echo "$VERSION" | grep -oP '\(\K[^\)]+' | head -1 | tr '[:upper:]' '[:lower:]')
    fi
fi

# --- Helper Functions ---
update_fn() {
    echo -e "${CYAN}Updating package repositories...${RESET}"
    case "$PACKAGE_MANAGER" in
        apt-get) $PACKAGE_MANAGER update -y > /dev/null ;;
        yum|dnf) $PACKAGE_MANAGER makecache -y > /dev/null ;;
        pacman) $PACKAGE_MANAGER -Sy > /dev/null ;;
        apk) $PACKAGE_MANAGER update > /dev/null ;;
    esac
}

install_docker () {
    case "$PACKAGE_MANAGER" in
        apt|apt-get)
            if ! command -v docker > /dev/null 2>&1; then
                echo -e "${GREEN}> docker is not installed, try install it.${RESET}"
                update_fn
                $PACKAGE_MANAGER install -y apt-transport-https ca-certificates lsb-release gnupg > /dev/null

                if [[ $ID == "ubuntu" ]]; then
                    $PACKAGE_MANAGER install -y software-properties-common > /dev/null
                fi

                curl -fsSL "https://download.docker.com/linux/${OS_DISTRO}/gpg" \
                    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
                    https://download.docker.com/linux/${OS_DISTRO} ${OS_CODENAME} stable" \
                    | tee /etc/apt/sources.list.d/docker.list > /dev/null

                update_fn
                $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null
                echo -e "${YELLOW}⚠️ Please logout/login to apply docker group.${RESET}"
            fi

            if command -v nvidia-smi > /dev/null 2>&1; then
                echo -e "${GREEN}find nvidia-smi, try install nvidia-docker2 package.${RESET}"
                distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
                curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
                curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
                update_fn
                $PACKAGE_MANAGER install -y nvidia-docker2 > /dev/null
            fi
            ;;
        pacman)
            if ! command -v docker > /dev/null 2>&1; then
                update_fn
                $PACKAGE_MANAGER -S --noconfirm docker > /dev/null
            fi

            if command -v nvidia-smi > /dev/null 2>&1; then
                $PACKAGE_MANAGER -S --noconfirm nvidia-container-toolkit > /dev/null
            fi
            ;;
        yum)
            if ! command -v docker > /dev/null 2>&1; then
                $PACKAGE_MANAGER install -y yum-utils > /dev/null
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null
            fi

            if command -v nvidia-smi > /dev/null 2>&1; then
                $PACKAGE_MANAGER install -y nvidia-docker2 > /dev/null
            fi
            ;;
        dnf)
            if ! command -v docker > /dev/null 2>&1; then
                $PACKAGE_MANAGER install -y dnf-plugins-core > /dev/null
                $PACKAGE_MANAGER config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null
            fi

            if command -v nvidia-smi > /dev/null 2>&1; then
                $PACKAGE_MANAGER install -y nvidia-docker2 > /dev/null
            fi
            ;;
        apk)
            if ! command -v docker > /dev/null 2>&1; then
                update_fn
                $PACKAGE_MANAGER add docker
            fi

            if command -v nvidia-smi > /dev/null 2>&1; then
                $PACKAGE_MANAGER add nvidia-container-toolkit > /dev/null
            fi
            ;;
        *)
            echo -e "${RED}❌ Unsupported package manager: ${PACKAGE_MANAGER}${RESET}"
            return 1
            ;;
    esac

    echo -e "${LIGHTGREEN}✅ Docker service check/install complete.${RESET}"
    
    # Start docker
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}Docker service is running.${RESET}"
    elif command -v systemctl > /dev/null 2>&1; then
        systemctl enable docker
        systemctl restart docker
    elif command -v service > /dev/null 2>&1; then
        service docker start
    else
        echo -e "${YELLOW}No systemd or service, running dockerd manually${RESET}"
        dockerd &
    fi
}

setup_directories() {
    echo -e "${CYAN}Setting up directory: ${APP_DIR}...${RESET}"
    mkdir -p "${APP_DIR}/data" "${APP_DIR}/logs"
    chmod -R 755 "${APP_DIR}"
}

configure_environment() {
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${CYAN} Environment Configuration (Bulk Paste)${RESET}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${CYAN}Paste your .env content below.${RESET}"
    echo -e "${YELLOW}Press Enter twice or Ctrl+D to finish:${RESET}"

    # Write directly to .env
    > "${APP_DIR}/.env"
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        echo "$line" >> "${APP_DIR}/.env"
    done

    echo -e "${GREEN}Successfully saved .env file to ${APP_DIR}/.env${RESET}"
}

harbor_login() {
    echo -e "${CYAN}Extracting Harbor credentials...${RESET}"
    STORE_URL=$(grep "^STORE_URL=" "${APP_DIR}/.env" | tail -n 1 | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
    STORE_USERNAME=$(grep "^STORE_USERNAME=" "${APP_DIR}/.env" | tail -n 1 | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
    STORE_PASSWORD=$(grep "^STORE_PASSWORD=" "${APP_DIR}/.env" | tail -n 1 | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")

    if [[ -z "$STORE_URL" || -z "$STORE_USERNAME" || -z "$STORE_PASSWORD" ]]; then
        echo -e "${RED}❌ Error: STORE_URL, STORE_USERNAME, or STORE_PASSWORD not found in .env${RESET}"
        exit 1
    fi

    echo -e "${CYAN}Logging in to Harbor at ${STORE_URL}...${RESET}"
    echo "$STORE_PASSWORD" | docker login "$STORE_URL" -u "$STORE_USERNAME" --password-stdin
}

generate_docker_compose() {
    echo -e "${GREEN}> Generating docker-compose.yml...${RESET}"
    cat > "${APP_DIR}/docker-compose.yml" <<EOF
services:
  app:
    image: \${EDGE_IMAGE}
    container_name: healthcare-edge-app
    privileged: true
    network_mode: "host"
    devices:
      - /dev/dri:/dev/dri

    env_file:
      - .env
    group_add:
      - video
      - "109"
    environment:
      - DISPLAY=:99
      - MESA_LOADER_DRIVER_OVERRIDE=iris
    volumes:
      - /dev:/dev
      - ./data:/app/data
      - ./logs:/app/logs
      - /etc/machine-id:/etc/machine-id:ro
    restart: unless-stopped
EOF
}

deploy_app() {
    echo -e "${CYAN}Pulling latest image and starting container...${RESET}"
    cd "${APP_DIR}"
    docker compose pull
    docker compose up -d

    echo -e "${LIGHTGREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${LIGHTGREEN} Deployment Successful!${RESET}"
    echo -e "${LIGHTGREEN} Location: ${APP_DIR}${RESET}"
    echo -e "${LIGHTGREEN} Container: healthcare-edge-app${RESET}"
    echo -e "${LIGHTGREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# --- Execution ---
APP_DIR="/app/healthcare"

install_docker
setup_directories
configure_environment
harbor_login
generate_docker_compose
deploy_app
