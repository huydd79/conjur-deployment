#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Full environment readiness, dependency installation, and Smart Host Sync.

# --- Source Configuration ---
if [ -f "./00.config.sh" ]; then
    source ./00.config.sh
else
    echo -e "\033[0;31m[ERROR] 00.config.sh not found!\033[0m"
    exit 1
fi

if [ "$READY" = false ]; then
    echo -e "${RED}[ERROR] Configuration is not ready in 00.config.sh. Set READY=true.${NC}"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 01: Full Environment & Host Readiness Check ---${NC}"

# --- 1. Check Required Conjur Image File ---
FULL_IMAGE_PATH="${UPLOAD_DIR}/${CONJUR_APPLIANCE_FILE}"
echo -ne "${CYAN}[CHECK]${NC} Checking for Conjur image file... "

if [ -f "$FULL_IMAGE_PATH" ]; then
    echo -e "${GREEN}Found${NC}"
else
    echo -e "${RED}Not Found${NC}"
    echo -e "${YELLOW}[TIP] Please upload ${CONJUR_APPLIANCE_FILE} to ${UPLOAD_DIR}${NC}"
    exit 1
fi

# --- 2. OS Detection and Package Manager Setup ---
if [ -x "$(command -v dnf)" ]; then
    PKG_MANAGER="dnf"
    INSTALL_CMD="dnf install -y"
    if [ -f /etc/redhat-release ]; then
        echo -e "${BLUE}[INFO]${NC} RHEL system detected. Ensuring EPEL repository is enabled..."
        $SUDO $INSTALL_CMD https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm
    fi
elif [ -x "$(command -v apt-get)" ]; then
    PKG_MANAGER="apt-get"
    INSTALL_CMD="apt-get install -y"
else
    echo -e "${RED}[ERROR] No supported package manager (dnf/apt) found.${NC}"
    exit 1
fi

# --- 3. Define and Install Required Packages ---
REQUIRED_PKGS=("jq" "curl" "openssl" "ca-certificates" "pv")

for PKG in "${REQUIRED_PKGS[@]}"; do
    echo -ne "${CYAN}[CHECK]${NC} Checking for ${PKG}... "
    if command -v "$PKG" &> /dev/null; then
        echo -e "${GREEN}Installed${NC}"
    else
        echo -e "${YELLOW}Missing. Installing...${NC}"
        $SUDO $INSTALL_CMD "$PKG"
        if [ $? -ne 0 ]; then
            echo -e "${RED}[ERROR] Failed to install ${PKG}.${NC}"
            exit 1
        fi
    fi
done

# --- 4. Container Manager Check & Installation ---
echo -ne "${CYAN}[CHECK]${NC} Checking for ${CONTAINER_MGR}... "
if command -v "$CONTAINER_MGR" &> /dev/null; then
    echo -e "${GREEN}Found${NC}"
else
    echo -e "${YELLOW}Not Found. Attempting to install ${CONTAINER_MGR}...${NC}"
    if [[ "$CONTAINER_MGR" == "podman" ]]; then
        $SUDO $INSTALL_CMD podman 
    elif [[ "$CONTAINER_MGR" == "docker" ]]; then
        [[ "$PKG_MANAGER" == "apt-get" ]] && $SUDO $INSTALL_CMD docker.io || $SUDO $INSTALL_CMD docker 
    fi
    
    if command -v "$CONTAINER_MGR" &> /dev/null; then
        echo -e "${GREEN}[SUCCESS] ${CONTAINER_MGR} installed.${NC}"
    else
        echo -e "${RED}[ERROR] Failed to install ${CONTAINER_MGR}.${NC}"
        exit 1
    fi
fi

# --- 5. SMART HOST UPDATE LOGIC ---
echo -e "${CYAN}[PROCESS]${NC} Synchronizing /etc/hosts with cluster configuration..."

add_or_update_host_entry() {
    local IP=$1
    local NAME=$2
    local FQDN="${NAME}.${CONJUR_DOMAIN}"
    local NEW_ENTRY="${IP}  ${NAME}  ${FQDN}"
    
    if grep -Fxq "$NEW_ENTRY" /etc/hosts; then
        echo -e "${GREEN}[OK]${NC} Host entry for ${FQDN} is already correct."
    else
        if grep -q "$FQDN" /etc/hosts; then
            echo -e "${YELLOW}[UPDATE]${NC} Outdated or incorrect entry found for ${FQDN}. Updating..."
            $SUDO sed -i "/$FQDN/d" /etc/hosts
        else
            echo -e "${BLUE}[INFO]${NC} Adding new entry for ${FQDN}..."
        fi
        echo "$NEW_ENTRY" | $SUDO tee -a /etc/hosts > /dev/null
    fi
}

# Add Leader VIP Entry
CLUSTER_NAME=${CONJUR_LEADER_FQDN%%.*}  # Getting first part of FQDN
if [ -n "$LEADER_VIP" ] && [ -n "$CLUSTER_NAME" ]; then
    add_or_update_host_entry "$LEADER_VIP" "$CLUSTER_NAME"
else
    echo -e "${RED}[ERROR] LEADER_VIP or CLUSTER_NAME is undefined in 00.config.sh${NC}"
    exit 1
fi

# Add Primary Node Entry
if [ -n "$PRIMARY_IP" ] && [ -n "$PRIMARY_NODE" ]; then
    add_or_update_host_entry "$PRIMARY_IP" "$PRIMARY_NODE"
else
    echo -e "${RED}[ERROR] PRIMARY_IP or PRIMARY_NODE is undefined in 00.config.sh${NC}"
    exit 1
fi

for i in "${!STANDBY_NODES[@]}"; do
    S_NAME="${STANDBY_NODES[$i]}"
    S_IP="${STANDBY_IPS[$i]}"
    if [ -n "$S_IP" ] && [ -n "$S_NAME" ]; then
        add_or_update_host_entry "$S_IP" "$S_NAME"
    fi
done

echo -e "${CYAN}========================================================${NC}"
echo -e "${GREEN}  Step 01 Finished: Env, Software, and Hosts are READY. ${NC}"
echo -e "${CYAN}========================================================${NC}"