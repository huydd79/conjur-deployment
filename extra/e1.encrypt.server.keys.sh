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

# --- Check if Configuration is Ready ---
if [ "$READY" = false ]; then
    echo -e "${RED}[ERROR] Configuration is not ready. Set READY=true in 00.config.sh${NC}"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 06: Server Key Encryption (SKE) Management ---${NC}"

# --- Paths Configuration (Updated path) ---
NODE_DATA_DIR="/opt/cyberark/$node_name"
HOST_SECURITY_DIR="${NODE_DATA_DIR}/security"
CONTAINER_SECURITY_DIR="/opt/cyberark/conjur/security"
MASTER_KEY_FILE="${CONTAINER_SECURITY_DIR}/master.key"

# --- Step 1: Host-side Permission Alignment ---
echo -e "${BLUE}[INFO] Aligning directory permissions for UID 1000...${NC}"
$SUDO chown -R 1000:1000 "$HOST_SECURITY_DIR"
$SUDO chmod 700 "$HOST_SECURITY_DIR"

# --- Step 2: Check Encryption Status ---
echo -e "${BLUE}[INFO] Checking current encryption status...${NC}"
IS_ENCRYPTED=$($SUDO $CONTAINER_MGR exec "$node_name" bash -c "ls /opt/conjur/etc/*.enc 2>/dev/null | wc -l")

if [ "$IS_ENCRYPTED" -gt 0 ]; then
    echo -e "${GREEN}[STATUS] System is already encrypted.${NC}"
else
    echo -e "${YELLOW}[STATUS] System is not yet encrypted. Starting encryption process...${NC}"

    # Step 2a: Generate Master Key if missing
    if [ ! -f "${HOST_SECURITY_DIR}/master.key" ]; then
        echo -e "${BLUE}[INFO] Generating random 32-byte master key...${NC}"
        $SUDO $CONTAINER_MGR exec "$node_name" bash -c "openssl rand 32 > $MASTER_KEY_FILE"
        $SUDO $CONTAINER_MGR exec "$node_name" chmod 600 "$MASTER_KEY_FILE"
    fi

    # Step 2b: Lock existing keys (required before encryption)
    echo -e "${BLUE}[INFO] Locking keys...${NC}"
    $SUDO $CONTAINER_MGR exec "$node_name" evoke keys lock

    # Step 2c: Encrypt keys using the master key
    echo -e "${BLUE}[INFO] Executing 'evoke keys encrypt'...${NC}"
    $SUDO $CONTAINER_MGR exec "$node_name" evoke keys encrypt "$MASTER_KEY_FILE"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] Encryption process failed!${NC}"
        exit 1
    fi
fi

# --- Step 3: Unlock Keys (Mandatory for service startup) ---
echo -e "${BLUE}[INFO] Unlocking keys into memory...${NC}"
$SUDO $CONTAINER_MGR exec "$node_name" evoke keys unlock "$MASTER_KEY_FILE"

# --- Step 4: Restart Services ---
echo -e "${BLUE}[INFO] Restarting Conjur services...${NC}"
$SUDO $CONTAINER_MGR exec "$node_name" sv restart conjur nginx pg seed

# --- Step 5: Final Hardening & Verification ---
echo -e "${CYAN}--- Final Verification ---${NC}"
sleep 5
HEALTH_OK=$(curl -k -s "https://localhost:$POC_CONJUR_HTTPS_PORT/health" | jq -r '.ok')

if [ "$HEALTH_OK" == "true" ]; then
    echo -e "${GREEN}[SUCCESS] Conjur is online and keys are secured.${NC}"
    $SUDO chown root:root "${HOST_SECURITY_DIR}/master.key"
    $SUDO chmod 600 "${HOST_SECURITY_DIR}/master.key"
else
    echo -e "${RED}[ERROR] System health check failed. Check logs with '$CONTAINER_MGR logs $node_name'.${NC}"
    exit 1
fi

echo -e "${CYAN}========================================================${NC}"
echo -e "${GREEN}  Step 06 Finished: SKE Management completed.           ${NC}"
echo -e "${BLUE}  Master Key: ${HOST_SECURITY_DIR}/master.key            ${NC}"
echo -e "${RED}  Note: Keep a secure backup of your master.key file!   ${NC}"
echo -e "${CYAN}========================================================${NC}"