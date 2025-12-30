#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Import 3rd Party Certificates for Leader and Followers. 

if [ -f "./00.config.sh" ]; then
    source ./00.config.sh
else
    echo -e "\033[0;31m[ERROR] 00.config.sh not found!\033[0m"
    exit 1
fi

if [ "$READY" = false ]; then
    echo -e "${RED}[ERROR] Configuration is not ready. Set READY=true in 00.config.sh${NC}"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 05: Import 3rd Party Certificates ---${NC}"

if [[ "$NODE_TYPE" != "primary" ]]; then
    echo -e "${RED}[ERROR] This node is configured as '${NODE_TYPE}'.${NC}"
    echo -e "${RED}[ERROR] Script 05 MUST only be executed on the PRIMARY (Leader) node.${NC}"
    exit 1
fi

LOCAL_CERT_DIR="./certs"
CA_CHAIN="ca-chain.pem"
MASTER_KEY="master-key.pem"
MASTER_CERT="master-cert.pem"
NODE_DATA_DIR="/opt/cyberark/$NODE_NAME"
NODE_CERT_DIR="${NODE_DATA_DIR}/certs"
CONTAINER_CERT_DIR="/opt/cyberark/conjur/certs"
TARGET_HOSTNAME="conjur-leader.${CONJUR_DOMAIN}"

for FILE in "$CA_CHAIN" "$MASTER_KEY" "$MASTER_CERT"; do
    if [ ! -f "${LOCAL_CERT_DIR}/$FILE" ]; then
        echo -e "${RED}[ERROR] Mandatory Leader file not found: ${LOCAL_CERT_DIR}/$FILE${NC}"
        exit 1
    fi
done

echo -e "${BLUE}[INFO] Validating if Leader cert covers: ${TARGET_HOSTNAME}...${NC}"
CERT_CN=$(openssl x509 -in "${LOCAL_CERT_DIR}/${MASTER_CERT}" -noout -subject | sed -n 's/.*CN[ ]*=[ ]*\([^,]*\).*/\1/p')
if [[ "$CERT_CN" != "$TARGET_HOSTNAME" ]]; then
    echo -e "${RED}[WARNING] Certificate does not explicitly list $TARGET_HOSTNAME${NC}"
    read -p "Do you want to ignore this and force install? (y/n): " CONFIRM
    [[ ! $CONFIRM =~ ^[Yy]$ ]] && exit 1
fi

$SUDO mkdir -p "$NODE_CERT_DIR"
$SUDO cp "${LOCAL_CERT_DIR}"/*.pem "$NODE_CERT_DIR/"
$SUDO chown root:root "$NODE_CERT_DIR"/*
$SUDO chmod 644 "${NODE_CERT_DIR}"/*

echo -e "${BLUE}[INFO] Importing certificates into Conjur container...${NC}"
$SUDO $CONTAINER_MGR exec "$NODE_NAME" evoke ca import --no-restart --root --force "${CONTAINER_CERT_DIR}/${CA_CHAIN}"
$SUDO $CONTAINER_MGR exec "$NODE_NAME" evoke ca import --no-restart --key "${CONTAINER_CERT_DIR}/${MASTER_KEY}" --set "${CONTAINER_CERT_DIR}/${MASTER_CERT}"

echo -e "${BLUE}[INFO] Restarting services to apply new certificates...${NC}"
$SUDO $CONTAINER_MGR exec "$NODE_NAME" sv restart conjur nginx pg seed

echo -e "${CYAN}--- Final Verification ---${NC}"
sleep 10
HEALTH_CHECK=$(curl -k -s "https://localhost:$CONJUR_HTTPS_PORT/health" | jq -r '.ok')

if [ "$HEALTH_CHECK" == "true" ]; then
    echo -e "${GREEN}[SUCCESS] Leader is healthy with 3rd party certificates.${NC}"
    $SUDO rm -f "${NODE_CERT_DIR}"/*.pem
else
    echo -e "${RED}[ERROR] Health check failed.${NC}"
    exit 1
fi
echo -e "${CYAN}========================================================${NC}"