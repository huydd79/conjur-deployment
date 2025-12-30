#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 26, 2025

# --- Source Configuration ---
if [ -f "./00.config.sh" ]; then
    source ./00.config.sh
else
    echo -e "\033[0;31m[ERROR] 00.config.sh not found!\033[0m"
    exit 1
fi

echo -e "${YELLOW}--- Conjur Auto-Recovery & Unlock Tool (Strict Management) ---${NC}"

# --- Paths Configuration (Updated path) ---
NODE_DATA_DIR="/opt/cyberark/$node_name"
HOST_SECURITY_DIR="${NODE_DATA_DIR}/security"
HOST_MASTER_KEY="${HOST_SECURITY_DIR}/master.key"
CONTAINER_MASTER_KEY="/opt/cyberark/conjur/security/master.key"

# --- Step 1: Validate Master Key Existence and Integrity ---
echo -ne "${CYAN}[CHECK]${NC} Verifying Master Key at ${HOST_MASTER_KEY}... "

if [ ! -f "$HOST_MASTER_KEY" ]; then
    echo -e "${RED}NOT FOUND!${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo -e "${RED}[REQUIRED]${NC} System is SKE-protected but the Master Key is missing."
    echo -e "${YELLOW}[ACTION]${NC} Please copy your backup 'master.key' to the host path:"
    echo -e "          ${GREEN}${HOST_MASTER_KEY}${NC}"
    echo -e "${YELLOW}[COMMAND EXAMPLE]${NC} sudo cp /path/to/backup/master.key ${HOST_MASTER_KEY}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    exit 1
else
    if [ ! -s "$HOST_MASTER_KEY" ]; then
        echo -e "${RED}EMPTY FILE!${NC}"
        echo -e "${RED}[ERROR]${NC} Master Key file exists but is empty (0 bytes)."
        echo -e "${YELLOW}[TIP]${NC} Replace it with a valid 32-byte key file."
        exit 1
    fi
    echo -e "${GREEN}VALID${NC}"
fi

# --- Step 2: Check Container Status ---
CONTAINER_STATUS=$($SUDO $CONTAINER_MGR inspect -f '{{.State.Status}}' "$node_name" 2>/dev/null)

if [ "$?" -ne 0 ]; then
    echo -e "${RED}[ERROR] Container '$node_name' does not exist. Run Step 03 first.${NC}"
    exit 1
fi

if [ "$CONTAINER_STATUS" != "running" ]; then
    echo -e "${BLUE}[INFO] Container is currently $CONTAINER_STATUS. Starting now...${NC}"
    $SUDO $CONTAINER_MGR start "$node_name"
    sleep 3
else
    echo -e "${GREEN}[OK] Container '$node_name' is already running.${NC}"
fi

# --- Step 3: Perform Keys Unlock ---
echo -e "${BLUE}[INFO] Preparing permissions and executing Unlock command...${NC}"

$SUDO chown 1000:1000 "$HOST_MASTER_KEY"
$SUDO chmod 600 "$HOST_MASTER_KEY"

$SUDO $CONTAINER_MGR exec "$node_name" evoke keys unlock "$CONTAINER_MASTER_KEY"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS] Keys decrypted and loaded into memory (Keyring).${NC}"
else
    echo -e "${RED}[ERROR] Failed to unlock keys. Please verify master.key content.${NC}"
    $SUDO chown root:root "$HOST_MASTER_KEY"
    exit 1
fi

# --- Step 4: Refresh Internal Services ---
echo -e "${BLUE}[INFO] Restarting Conjur internal services...${NC}"
$SUDO $CONTAINER_MGR exec "$node_name" sv restart conjur nginx pg seed

# --- Step 5: Final Health Verification ---
echo -e "${CYAN}--- Verifying System Health Status ---${NC}"
sleep 5
HEALTH_CHECK=$(curl -k -s "https://localhost:$POC_CONJUR_HTTPS_PORT/health" | jq -r '.ok' 2>/dev/null)

if [ "$HEALTH_CHECK" == "true" ]; then
    echo -e "${GREEN}[READY] Conjur Leader is back online and fully functional!${NC}"
else
    echo -e "${RED}[FAILED] Health check failed. Check logs: $CONTAINER_MGR logs $node_name${NC}"
fi

$SUDO chown root:root "$HOST_MASTER_KEY"
$SUDO chmod 600 "$HOST_MASTER_KEY"

echo -e "${CYAN}========================================================${NC}"