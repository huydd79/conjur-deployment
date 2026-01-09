#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: January 09, 2026
# Description: Offline Environment readiness for RHEL 9 Minimal (Air-gapped).

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

echo -e "${YELLOW}--- Starting Step 01: Offline Environment Readiness Check (RHEL 9) ---${NC}"

# --- 1. Define Paths ---
RPM_DIR="/opt/upload/rpms"
FULL_IMAGE_PATH="${UPLOAD_DIR}/${CONJUR_APPLIANCE_FILE}"

# --- 2. Check Required Files ---
echo -ne "${CYAN}[CHECK]${NC} Checking for Conjur image file... "
if [ -f "$FULL_IMAGE_PATH" ]; then
    echo -e "${GREEN}Found${NC}"
else
    echo -e "${RED}Not Found${NC} (Path: $FULL_IMAGE_PATH)"
    exit 1
fi

echo -ne "${CYAN}[CHECK]${NC} Checking for RPM repository directory... "
if [ -d "$RPM_DIR" ]; then
    echo -e "${GREEN}Found${NC}"
else
    echo -e "${RED}Not Found${NC} (Path: $RPM_DIR)"
    echo -e "${YELLOW}[TIP] Please upload all required RPMs to $RPM_DIR${NC}"
    exit 1
fi

# --- 3. Offline Installation Logic ---
echo -e "${BLUE}[INFO]${NC} Installing dependencies from local RPM directory..."

# Chúng ta sử dụng dnf install trên toàn bộ thư mục để dnf tự giải quyết các phụ thuộc chéo giữa các file RPM local.
$SUDO dnf install -y "$RPM_DIR"/*.rpm

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS] Local RPM installation completed.${NC}"
else
    echo -e "${RED}[ERROR] Failed to install local RPMs. Check for missing dependencies in $RPM_DIR.${NC}"
    exit 1
fi

# --- 4. Verify Required Tools ---
# Lưu ý: 'nc' được cung cấp bởi gói nmap-ncat
REQUIRED_TOOLS=("jq" "curl" "openssl" "pv" "nc" "tar" "$CONTAINER_MGR")

for TOOL in "${REQUIRED_TOOLS[@]}"; do
    echo -ne "${CYAN}[CHECK]${NC} Verifying tool: ${TOOL}... "
    if command -v "$TOOL" &> /dev/null; then
        echo -e "${GREEN}Available${NC}"
    else
        echo -e "${RED}Missing!${NC}"
        echo -e "${YELLOW}[DEBUG] Tool '$TOOL' was not found in PATH after RPM install.${NC}"
        exit 1
    fi
done

# --- 5. SMART HOST UPDATE LOGIC (Giữ nguyên vì đây là thao tác local) ---
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

# Leader VIP
CLUSTER_NAME_PREFIX=${CONJUR_LEADER_FQDN%%.*}
if [ -n "$LEADER_VIP" ]; then
    add_or_update_host_entry "$LEADER_VIP" "$CLUSTER_NAME_PREFIX"
fi

# Primary Node
if [ -n "$PRIMARY_IP" ]; then
    add_or_update_host_entry "$PRIMARY_IP" "$PRIMARY_NODE"
fi

# Standby Nodes
for i in "${!STANDBY_NODES[@]}"; do
    add_or_update_host_entry "${STANDBY_IPS[$i]}" "${STANDBY_NODES[$i]}"
done

# Follower Nodes
for i in "${!FOLLOWER_NODES[@]}"; do
    add_or_update_host_entry "${FOLLOWER_IPS[$i]}" "${FOLLOWER_NODES[$i]}"
done

echo -e "${CYAN}========================================================${NC}"
echo -e "${GREEN} Step 01 Finished: Offline Environment is READY. ${NC}"
echo -e "${CYAN}========================================================${NC}"