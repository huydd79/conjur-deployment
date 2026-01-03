#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Configure Conjur Leader. Includes Primary-only check.

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

echo -e "${YELLOW}--- Starting Step 04: Configure Conjur Leader ---${NC}"

if [[ "$NODE_TYPE" != "primary" ]]; then
    echo -e "${RED}[ERROR] This node is configured as '${NODE_TYPE}'.${NC}"
    echo -e "${RED}[ERROR] Script 04 MUST only be executed on the PRIMARY (Leader) node.${NC}"
    exit 1
fi

echo -e "${GREEN}[PROCEED] Node is confirmed as PRIMARY. Starting configuration...${NC}"

LEADER_CONTAINER=$CONTAINER_NAME
CLUSTER_DNS=$CONJUR_LEADER_FQDN
NODE_FQDN="${NODE_NAME}.${CONJUR_DOMAIN}"    
STANDBY_FQDNS_LIST=$(printf ",%s.${CONJUR_DOMAIN}" "${STANDBY_NODES[@]}")
ALL_ALT_NAMES="${CLUSTER_DNS},${NODE_FQDN}${STANDBY_FQDNS_LIST}"

echo -e "${BLUE}[INFO] Running 'evoke configure leader' inside container...${NC}"

$SUDO $CONTAINER_MGR exec "$LEADER_CONTAINER" evoke configure leader \
    --accept-eula \
    --hostname "$CLUSTER_DNS" \
    --leader-altnames "${ALL_ALT_NAMES}" \
    --admin-password "$CONJUR_ADMIN_PW" \
    "$CONJUR_ACCOUNT"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS] Conjur Leader has been configured successfully.${NC}"
else
    echo -e "${RED}[ERROR] Configuration failed. Check container logs.${NC}"
    exit 1
fi

echo -e "${CYAN}--- Verifying Leader Health Endpoint ---${NC}"
sleep 5
curl -k -s "https://localhost:$CONJUR_HTTPS_PORT/health" | jq || echo -e "${YELLOW}[WARN] Could not reach health endpoint yet.${NC}"

echo -e "${CYAN}========================================================${NC}"
echo -e "${GREEN}  Step 04 Finished: Leader is ready for usage.          ${NC}"
echo -e "${YELLOW}  Web UI: https://${CLUSTER_DNS}:${CONJUR_HTTPS_PORT}/ui ${NC}"
echo -e "${CYAN}========================================================${NC}"