#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: January 05, 2026 (Updated)
# Description: Unified script to start Conjur Appliance and configure systemd persistence.

if [ -f "./00.config.sh" ]; then
    source ./00.config.sh
else
    echo -e "\033[0;31m[ERROR] 00.config.sh not found!\033[0m"
    exit 1
fi

if [ "$READY" = false ]; then
    echo -e "${RED}[ERROR] Configuration is not ready.${NC}"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 03: Initialize Unified Conjur Appliance Container ---${NC}"
echo -e "${BLUE}[INFO]${NC} Deploying as: ${NODE_TYPE}"

echo -ne "${CYAN}[CHECK]${NC} Detecting Conjur image for version ${CONJUR_VERSION}... "
DETECTED_IMAGE=$($SUDO $CONTAINER_MGR images --format "{{.Repository}}:{{.Tag}}" | grep ":${CONJUR_VERSION}" | cut -d':' -f1 | head -n1)

if [ -z "$DETECTED_IMAGE" ]; then
    echo -e "${RED}Not Found!${NC}"
    exit 1
else
    FULL_IMAGE_TAG="${DETECTED_IMAGE}:${CONJUR_VERSION}"
    echo -e "${GREEN}Found: ${FULL_IMAGE_TAG}${NC}"
fi

echo -e "${BLUE}[INFO] Cleaning up existing container: ${CONTAINER_NAME}...${NC}"
$SUDO $CONTAINER_MGR stop "$CONTAINER_NAME" &> /dev/null
$SUDO $CONTAINER_MGR rm -f "$CONTAINER_NAME" &> /dev/null

echo -e "${BLUE}[INFO] Preparing persistent volumes in ${NODE_DATA_DIR}...${NC}"

$SUDO mkdir -p "${NODE_DATA_DIR}"/{security,config,backups,seeds,logs,certs}
$SUDO touch "${NODE_DATA_DIR}"/config/conjur.yml
$SUDO chmod o+x "${NODE_DATA_DIR}"/config
$SUDO chmod o+r "${NODE_DATA_DIR}"/config/conjur.yml
$SUDO cp ./policies/secomp.json "${NODE_DATA_DIR}"/security
echo -e "${BLUE}[INFO] Starting Conjur container...${NC}"

$SUDO $CONTAINER_MGR run \
    --name "$CONTAINER_NAME" \
    --detach \
    --restart=unless-stopped \
    --security-opt seccomp="${NODE_DATA_DIR}/security/secomp.json" \
    --publish "$CONJUR_HTTPS_PORT:443" \
    --publish "444:444" \
    --publish "5432:5432" \
    --publish "1999:1999" \
    --cap-add AUDIT_WRITE \
    --log-driver journald \
    --volume "${NODE_DATA_DIR}/config:/etc/conjur/config:z" \
    --volume "${NODE_DATA_DIR}/security:/opt/cyberark/conjur/security:z" \
    --volume "${NODE_DATA_DIR}/backups:/opt/conjur/backup:z" \
    --volume "${NODE_DATA_DIR}/seeds:/opt/cyberark/conjur/seeds:Z" \
    --volume "${NODE_DATA_DIR}/logs:/var/log/conjur:z" \
    --volume "${NODE_DATA_DIR}/certs:/opt/cyberark/conjur/certs:z" \
    "$FULL_IMAGE_TAG"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS] Conjur container '${CONTAINER_NAME}' is running.${NC}"
else
    echo -e "${RED}[ERROR] Failed to start Conjur container.${NC}"
    exit 1
fi

# --- NEW: Step 11 - Create systemd service for Podman ---
if [ "$CONTAINER_MGR" == "podman" ]; then
    echo -e "${YELLOW}--- Step 11: Create systemd service for Podman ---${NC}"
    
    CONTAINER_ID=$($SUDO podman ps --filter "name=$CONTAINER_NAME" --format "{{.ID}}")
    SERVICE_FILE="/etc/systemd/system/conjur.service"

    echo -e "${BLUE}[INFO]${NC} Generating systemd unit for Container ID: ${CONTAINER_ID}"
    
    # Generate and save the service file
    $SUDO podman generate systemd "$CONTAINER_ID" \
        --name \
        --container-prefix="" \
        --separator="" | $SUDO tee "$SERVICE_FILE" > /dev/null

    echo -e "${BLUE}[INFO]${NC} Enabling and starting conjur.service..."
    $SUDO systemctl daemon-reload
    $SUDO systemctl enable conjur.service
    
    # Cần restart để systemd thực sự nắm quyền quản lý container
    $SUDO systemctl restart conjur.service
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS] systemd service 'conjur.service' is active.${NC}"
    else
        echo -e "${RED}[ERROR] Failed to initialize systemd service.${NC}"
    fi
fi

# --- NEW: Step 12 - Persist user processes (Linger) ---
echo -e "${YELLOW}--- Step 12: Persist user processes ---${NC}"
echo -e "${BLUE}[INFO]${NC} Enabling linger for root user..."
$SUDO loginctl enable-linger root

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS] Linger enabled for root.${NC}"
else
    echo -e "${RED}[WARNING] Failed to enable linger.${NC}"
fi

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}  Initialization Complete!${NC}"
echo -e "${BLUE}  Node is ready for 'evoke configure leader' OR 'evoke unpack seed'.${NC}"
echo -e "${GREEN}================================================================${NC}"

echo -e "${CYAN}--- Final Container Status ---${NC}"
$SUDO $CONTAINER_MGR ps | grep "$CONTAINER_NAME"