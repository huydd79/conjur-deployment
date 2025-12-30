#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Unified script to start Conjur Appliance for both Primary and Standby.

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

echo -e "${BLUE}[INFO] Cleaning up existing container: ${NODE_NAME}...${NC}"
$SUDO $CONTAINER_MGR stop "$NODE_NAME" &> /dev/null
$SUDO $CONTAINER_MGR rm -f "$NODE_NAME" &> /dev/null

NODE_DATA_DIR="/opt/cyberark/$NODE_NAME"
echo -e "${BLUE}[INFO] Preparing persistent volumes in ${NODE_DATA_DIR}...${NC}"

$SUDO mkdir -p "${NODE_DATA_DIR}"/{security,config,backups,seeds,logs,certs}
$SUDO chmod o+x "${NODE_DATA_DIR}/config"

echo -e "${BLUE}[INFO] Starting Conjur container...${NC}"

$SUDO $CONTAINER_MGR run \
    --name "$NODE_NAME" \
    --detach \
    --restart=unless-stopped \
    --security-opt seccomp=unconfined \
    --publish "$CONJUR_HTTPS_PORT:443" \
    --publish "444:444" \
    --publish "5432:5432" \
    --publish "1999:1999" \
    --cap-add AUDIT_WRITE \
    --volume "${NODE_DATA_DIR}/config:/etc/conjur/config:Z" \
    --volume "${NODE_DATA_DIR}/security:/opt/cyberark/conjur/security:Z" \
    --volume "${NODE_DATA_DIR}/backups:/opt/conjur/backup:Z" \
    --volume "${NODE_DATA_DIR}/seeds:/opt/cyberark/conjur/seeds:Z" \
    --volume "${NODE_DATA_DIR}/logs:/var/log/conjur:Z" \
    --volume "${NODE_DATA_DIR}/certs:/opt/cyberark/conjur/certs:Z" \
    "$FULL_IMAGE_TAG"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS] Conjur container '${NODE_NAME}' is running.${NC}"
    echo -e "${BLUE}[INFO] Node is ready for 'evoke configure leader' OR 'evoke unpack seed'.${NC}"
else
    echo -e "${RED}[ERROR] Failed to start Conjur container.${NC}"
    exit 1
fi

echo -e "${CYAN}--- Container Status ---${NC}"
$SUDO $CONTAINER_MGR ps | grep "$NODE_NAME"