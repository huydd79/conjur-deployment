#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 30, 2025
# Description: Step 06 - Activate Standby nodes from Primary Leader.

if [ -f "./00.config.sh" ]; then source ./00.config.sh; else exit 1; fi

if [[ "$NODE_TYPE" != "primary" ]]; then
    echo -e "${RED}[ERROR] This script must only be executed on the PRIMARY node.${NC}"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 06: Standby Activation Process ---${NC}"

SSH_USER="root"
PRIMARY_FQDN="${PRIMARY_NODE}.${CONJUR_DOMAIN}"

for i in "${!STANDBY_NODES[@]}"; do
    S_NAME="${STANDBY_NODES[$i]}"
    S_FQDN="${S_NAME}.${CONJUR_DOMAIN}"
    SEED_FILE="/tmp/${S_NAME}_seed.tar.gz"

    echo -e "\n${BLUE}========================================================${NC}"
    echo -e " TARGET STANDBY: ${S_FQDN}"
    echo -e "${BLUE}========================================================${NC}"

    echo -ne "  -> Checking connectivity & node role... "
    if ! ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 "${SSH_USER}@${S_FQDN}" "$CONTAINER_MGR exec ${S_NAME} evoke role show" | grep -q "blank"; then
        echo -e "${RED}NOT BLANK OR UNREACHABLE${NC} (Skipping)"
        continue
    fi
    echo -e "${GREEN}READY${NC}"

    echo -ne "  -> Generating Standby Seed... "
    $CONTAINER_MGR exec "${PRIMARY_NODE}" evoke seed standby "${S_FQDN}" "${PRIMARY_FQDN}" 1> "${SEED_FILE}" 2>/dev/null
    
    if [[ ! -s "${SEED_FILE}" ]]; then echo -e "${RED}FAILED${NC}"; continue; fi
    echo -e "${GREEN}DONE${NC}"

    scp -q -o StrictHostKeyChecking=no "${SEED_FILE}" "${SSH_USER}@${S_FQDN}:/tmp/"
    
    ssh -o StrictHostKeyChecking=no "${SSH_USER}@${S_FQDN}" "bash -s" << EOF
        ${CONTAINER_MGR} cp /tmp/${S_NAME}_seed.tar.gz ${S_NAME}:/tmp/seed.tar.gz
        ${CONTAINER_MGR} exec ${S_NAME} evoke unpack seed /tmp/seed.tar.gz
        ${CONTAINER_MGR} exec ${S_NAME} evoke configure standby
        rm -f /tmp/${S_NAME}_seed.tar.gz
EOF

    if [ $? -eq 0 ]; then echo -e "  -> ${GREEN}SUCCESS:${NC} Active."; else echo -e "  -> ${RED}ERROR${NC}"; fi
    rm -f "${SEED_FILE}"
done

echo -e "\n${CYAN}========================================================${NC}"
echo -e "${GREEN} Step 06 Complete: Standby nodes provisioned.            ${NC}"
echo -e "${CYAN}========================================================${NC}"