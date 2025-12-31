#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Import 3rd Party Certificates for Leader and Followers. 
# Strategy: Set HTTPS for Leader (--set) and pre-load Follower identities into the store.

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

echo -e "${YELLOW}--- Starting Step 05: Import 3rd Party Certificates ---${NC}"

# --- Step 1: Guard Clause - Check if Node is Primary ---
if [[ "$NODE_TYPE" != "primary" ]]; then
    echo -e "${RED}[ERROR] This node is configured as '${NODE_TYPE}'.${NC}"
    echo -e "${RED}[ERROR] Script 05 MUST only be executed on the PRIMARY (Leader) node.${NC}"
    exit 1
fi

echo -e "${GREEN}[PROCEED] Node is confirmed as PRIMARY. Starting certificate import...${NC}"

# --- Step 2: Define Paths & Targets ---
LOCAL_CERT_DIR="./certs"
CA_CHAIN="ca-chain.pem"
MASTER_KEY="master-key.pem"
MASTER_CERT="master-cert.pem"

NODE_DATA_DIR="/opt/cyberark/$NODE_NAME"
NODE_CERT_DIR="${NODE_DATA_DIR}/certs"
CONTAINER_CERT_DIR="/opt/cyberark/conjur/certs"

# Target Hostname calculation for Leader
TARGET_HOSTNAME=$CONJUR_LEADER_FQDN

# --- Step 3: Mandatory File Existence Check (Leader) ---
for FILE in "$CA_CHAIN" "$MASTER_KEY" "$MASTER_CERT"; do
    if [ ! -f "${LOCAL_CERT_DIR}/$FILE" ]; then
        echo -e "${RED}[ERROR] Mandatory Leader file not found: ${LOCAL_CERT_DIR}/$FILE${NC}"
        exit 1
    fi
done

# --- Step 4: Validate Leader Certificate SAN/CN ---
echo -e "${BLUE}[INFO] Validating if Leader cert covers: ${TARGET_HOSTNAME}...${NC}"
CERT_DNS_LIST=$(openssl x509 -in "${LOCAL_CERT_DIR}/${MASTER_CERT}" -text -noout | grep -oP 'DNS:[^, ]+' | sed 's/DNS://g')
CERT_CN=$(openssl x509 -in "${LOCAL_CERT_DIR}/${MASTER_CERT}" -noout -subject | sed -n 's/.*CN[ ]*=[ ]*\([^,]*\).*/\1/p')

ALL_ENTRIES="$CERT_CN $CERT_DNS_LIST"
IS_VALID=false

for ENTRY in $ALL_ENTRIES; do
    if [[ "$ENTRY" == "$TARGET_HOSTNAME" ]]; then
        IS_VALID=true; break
    fi
done

if [ "$IS_VALID" = false ]; then
    echo -e "${RED}[WARNING] Certificate does not explicitly list $TARGET_HOSTNAME${NC}"
    read -p "Do you want to ignore this and force install? (y/n): " CONFIRM
    [[ ! $CONFIRM =~ ^[Yy]$ ]] && exit 1
fi

# --- Step 5: Copy All Certs to Node Storage ---
echo -e "${BLUE}[INFO] Syncing all certificates to node storage...${NC}"
$SUDO mkdir -p "$NODE_CERT_DIR"
$SUDO cp "${LOCAL_CERT_DIR}"/*.pem "$NODE_CERT_DIR/"
$SUDO chown root:root "$NODE_CERT_DIR"/*
$SUDO chmod 644 "${NODE_CERT_DIR}"/*

# --- Step 6: Import into Conjur ---
echo -e "${BLUE}[INFO] Importing certificates into Conjur container...${NC}"

# 6.1 Import Root CA
echo "  -> Importing Root CA Chain..."
$SUDO $CONTAINER_MGR exec "$NODE_NAME" evoke ca import --no-restart --root --force "${CONTAINER_CERT_DIR}/${CA_CHAIN}"

# 6.2 Import and Set Leader HTTPS Certificate
echo "  -> Setting Leader HTTPS Identity..."
$SUDO $CONTAINER_MGR exec "$NODE_NAME" evoke ca import --no-restart \
    --key "${CONTAINER_CERT_DIR}/${MASTER_KEY}" \
    --set \
    "${CONTAINER_CERT_DIR}/${MASTER_CERT}"

# 6.3 Import Follower Certificates (Looping through directory)
echo "  -> Pre-loading Follower Identities into Store..."
for CERT_PATH in "${LOCAL_CERT_DIR}"/follower-*-cert.pem; do
    [ -e "$CERT_PATH" ] || continue # Handle case where no follower certs exist
    
    FILE_NAME=$(basename "$CERT_PATH")
    # Identify corresponding key file (replace -cert.pem with -key.pem)
    KEY_FILE_NAME="${FILE_NAME/-cert.pem/-key.pem}"
    
    if [ -f "${LOCAL_CERT_DIR}/$KEY_FILE_NAME" ]; then
        echo "     - Found: $FILE_NAME"
        $SUDO $CONTAINER_MGR exec "$NODE_NAME" evoke ca import --no-restart \
            --key "${CONTAINER_CERT_DIR}/$KEY_FILE_NAME" \
            "${CONTAINER_CERT_DIR}/$FILE_NAME"
    else
        echo -e "${YELLOW}     [SKIP] Key missing for $FILE_NAME${NC}"
    fi
done

# --- Step 7: Restart & Health Check ---
echo -e "${BLUE}[INFO] Restarting services to apply new certificates...${NC}"
$SUDO $CONTAINER_MGR exec "$NODE_NAME" sv restart conjur nginx pg seed

echo -e "${CYAN}--- Final Verification ---${NC}"
sleep 10
HEALTH_CHECK=$(curl -k -s "https://localhost:$CONJUR_HTTPS_PORT/health" | jq -r '.ok')

if [ "$HEALTH_CHECK" == "true" ]; then
    echo -e "${GREEN}[SUCCESS] Leader is healthy with 3rd party certificates.${NC}"
    
    # --- Step 8: Security Cleanup ---
    echo -e "${YELLOW}[SECURITY] Cleaning up PEM files from node storage...${NC}"
    $SUDO rm -f "${NODE_CERT_DIR}"/*.pem
else
    echo -e "${RED}[ERROR] Health check failed. Check logs: $CONTAINER_MGR logs $NODE_NAME${NC}"
    exit 1
fi

echo -e "${CYAN}========================================================${NC}"