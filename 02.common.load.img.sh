#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 26, 2025

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

echo -e "${YELLOW}--- Starting Step 02: Load Conjur Image with Progress Bar ---${NC}"
FULL_IMAGE_PATH="${UPLOAD_DIR}/${CONJUR_APPLIANCE_FILE}"

if ! command -v pv &> /dev/null; then
    echo -e "${YELLOW}[WARN] 'pv' not found. Loading without progress bar...${NC}"
    $SUDO $CONTAINER_MGR load -i "$FULL_IMAGE_PATH"
else
    echo -e "${BLUE}[INFO] Loading Conjur appliance image...${NC}"
    pv "$FULL_IMAGE_PATH" | $SUDO $CONTAINER_MGR load
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS] Conjur image loaded successfully.${NC}"
else
    echo -e "${RED}[ERROR] Failed to load the image.${NC}"
    exit 1
fi

$SUDO $CONTAINER_MGR images | grep -i "conjur"