#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 30, 2025
# Description: Step 07 - Activate Followers using Leader's Internal CA.

if [ -f "./00.config.sh" ]; then source ./00.config.sh; else exit 1; fi

if [[ "$NODE_TYPE" != "primary" ]]; then
    echo -e "${RED}[ERROR] This script must only be executed on the PRIMARY node.${NC}"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 07: Follower Activation ---${NC}"

SSH_USER="root"
PRIMARY_FQDN="${PRIMARY_NODE}.${CONJUR_DOMAIN}"

for i in "${!FOLLOWER_NODES[@]}"; do
    F_NAME="${FOLLOWER_NODES[$i]}"
    F_FQDN="${F_NAME}.${CONJUR_DOMAIN}"
    SEED_FILE="/tmp/${F_NAME}_seed.tar.gz"

    echo -e "\n${BLUE}========================================================${NC}"
    echo -e " TARGET FOLLOWER: ${F_FQDN}"
    echo -e "${BLUE}========================================================${NC}"

    $CONTAINER_MGR exec "${PRIMARY_NODE}" evoke seed follower --replication-set full "${F_FQDN}" "${PRIMARY_FQDN}" 1> "${SEED_FILE}"
    
    scp -q -o StrictHostKeyChecking=no "${SEED_FILE}" "${SSH_USER}@${F_FQDN}:/tmp/"
    
    ssh -o StrictHostKeyChecking=no "${SSH_USER}@${F_FQDN}" "bash -s" << EOF
        ${CONTAINER_MGR} cp /tmp/${F_NAME}_seed.tar.gz ${F_NAME}:/tmp/seed.tar.gz
        ${CONTAINER_MGR} exec ${F_NAME} evoke unpack seed /tmp/seed.tar.gz
        ${CONTAINER_MGR} exec ${F_NAME} evoke configure follower
        rm -f /tmp/${F_NAME}_seed.tar.gz
EOF

    rm -f "${SEED_FILE}"
done

echo -e "\n${CYAN}========================================================${NC}"
echo -e "${GREEN} Step 07 Complete: Followers successfully provisioned.   ${NC}"
echo -e "${CYAN}========================================================${NC}"