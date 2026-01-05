#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Step 13 - Remote Auto-Failover Enrollment for Standby nodes.
# Strategy: Remote execution of 'evoke cluster enroll' via SSH from Primary.

# --- Source Configuration ---
if [ -f "./00.config.sh" ]; then
    source ./00.config.sh
else
    echo -e "\033[0;31m[ERROR] 00.config.sh not found!\033[0m"
    exit 1
fi

if [ "$READY" = false ]; then
    echo -e "${RED}[ERROR] Configuration is not ready in 00.config.sh. Set READY=true.${NC}"
    exit 1
fi

# --- Guard Clause ---
if [[ "$NODE_TYPE" != "primary" ]]; then
    echo -e "${RED}[ERROR] This script must only be executed on the PRIMARY node.${NC}"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 13: Remote Standby Enrollment Process ---${NC}"

SSH_USER="root"
LEADER_FQDN=$PRIMARY_NODE.${CONJUR_DOMAIN}

# --- Standby Enrollment Loop ---
for i in "${!STANDBY_NODES[@]}"; do
    S_NAME="${STANDBY_NODES[$i]}"
    S_FQDN="${S_NAME}.${CONJUR_DOMAIN}"

    echo -e "\n${BLUE}========================================================${NC}"
    echo -e " TARGET STANDBY: ${S_FQDN}"
    echo -e "${BLUE}========================================================${NC}"

    # 1. CHECK CONNECTIVITY & ROLE
    echo -ne "  -> Verifying standby role readiness... "
    # The node must be in 'standby' role (activated by Step 06) before it can be enrolled in a cluster
    CURRENT_ROLE=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 "${SSH_USER}@${S_FQDN}" "$CONTAINER_MGR exec ${CONTAINER_NAME} evoke role show" 2>/dev/null)
    
    if [[ "$CURRENT_ROLE" != "standby" ]]; then
        echo -e "${RED}FAILED${NC}"
        echo -e "     [REASON] Node is in '$CURRENT_ROLE' role. It must be 'standby' (Run Step 06 first)."
        continue
    fi
    echo -e "${GREEN}READY${NC}"

    # 2. REMOTE CLUSTER ENROLLMENT
    echo -e "  -> Triggering remote cluster enrollment..."
    echo -e "     - Cluster Name : ${CLUSTER_NAME}"
    echo -e "     - Master FQDN  : ${LEADER_FQDN}"

    ssh -o StrictHostKeyChecking=no "${SSH_USER}@${S_FQDN}" "bash -s" << EOF
        set -e
        echo "     - Executing enroll command inside container..."
        ${CONTAINER_MGR} exec ${CONTAINER_NAME} evoke cluster enroll -n ${S_FQDN} -m ${LEADER_FQDN} ${CLUSTER_NAME}
EOF

    if [ $? -eq 0 ]; then
        echo -e "  -> ${GREEN}SUCCESS:${NC} ${S_NAME} enrolled in cluster ${CLUSTER_NAME}."
    else
        echo -e "  -> ${RED}ERROR:${NC} Enrollment failed for ${S_NAME}."
        continue
    fi

    # 3. VERIFY HEALTH VIA PORT 444
    echo -ne "  -> Verifying replication health... "
    sleep 2
    # Check if the node reports 'standing_by' status on port 444
    HEALTH_STATUS=$(ssh -o StrictHostKeyChecking=no "${SSH_USER}@${S_FQDN}" "curl -s http://localhost:444/health")
    IS_STANDING_BY=$(echo $HEALTH_STATUS | grep -q '"status":"standing_by"' && echo "true" || echo "false")
    
    if [[ "$IS_STANDING_BY" == "true" ]]; then
        echo -e "${GREEN}OK (Standing By)${NC}"
    else
        echo -e "${YELLOW}WARNING (Check health manually)${NC}"
        echo -e "     [RAW] $HEALTH_STATUS"
    fi
done

echo -e "\n${CYAN}========================================================${NC}"
echo -e "${GREEN} Step 13 Finished: All Standby nodes enrolled.          ${NC}"
echo -e "${CYAN}========================================================${NC}"