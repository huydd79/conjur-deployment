#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 30, 2025
# Description: Step 06 - Activate Standby nodes from Primary Leader.
# Strategy: Binary clean seed generation and explicit remote error reporting.

if [ -f "./00.config.sh" ]; then source ./00.config.sh; else exit 1; fi

# --- Guard Clause ---
if [[ "$NODE_TYPE" != "primary" ]]; then
    echo -e "${RED}[ERROR] This script must only be executed on the PRIMARY node.${NC}"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 06: Standby Activation Process ---${NC}"

SSH_USER="root"
CLUSTER_FQDN=$CONJUR_LEADER_FQDN

# ==========================================================
# PRE-CHECK: API (443) & POSTGRES (5432)
# ==========================================================
echo -e "${BLUE}[PRE-CHECK]${NC} Verifying Cluster Connectivity ($CLUSTER_FQDN)..."

# 1. Check HTTPS Health (API Layer)
echo -ne "  -> API Health (443): "
HTTP_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" "https://${CLUSTER_FQDN}/health")
if [[ "$HTTP_STATUS" == "200" ]]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED (HTTP $HTTP_STATUS)${NC}"
    ERROR_FOUND=true
fi

# 2. Check Postgres Port (Replication Layer)
echo -ne "  -> Postgres Port (5432): "
# nc -z: scan mode, -w 3: timeout 3 seconds
nc -z -w 3 "$CLUSTER_FQDN" 5432 > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}OPEN${NC}"
else
    echo -e "${RED}CLOSED${NC}"
    ERROR_FOUND=true
fi

# Final Decision for Pre-check
if [[ "$ERROR_FOUND" == true ]]; then
    echo -e "--------------------------------------------------------"
    echo -e "${RED}[ERROR] Infrastructure Check Failed!${NC}"
    echo -e "${YELLOW}[ADVICE]${NC} Ensure HAProxy is configured to proxy BOTH 443 and 5432."
    echo -e "--------------------------------------------------------"
    exit 1
fi
echo -e "${GREEN}[SUCCESS] All Cluster ports are reachable. Proceeding...${NC}"
# ==========================================================

# --- Standby Activation Loop ---
for i in "${!STANDBY_NODES[@]}"; do
    S_NAME="${STANDBY_NODES[$i]}"
    S_FQDN="${S_NAME}.${CONJUR_DOMAIN}"
    SEED_FILE="/tmp/${S_NAME}_seed.tar.gz"

    echo -e "\n${BLUE}========================================================${NC}"
    echo -e " TARGET STANDBY: ${S_FQDN}"
    echo -e "${BLUE}========================================================${NC}"

    # 1. CHECK READINESS & ROLE
    echo -ne "  -> Checking connectivity & node role... "
    # Check if the host is reachable and the container is in 'blank' state
    if ! ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 "${SSH_USER}@${S_FQDN}" "$CONTAINER_MGR exec ${S_NAME} evoke role show" | grep -q "blank"; then
        echo -e "${RED}NOT BLANK OR UNREACHABLE${NC} (Skipping)"
        continue
    fi
    echo -e "${GREEN}READY${NC}"

    # 2. GENERATE STANDBY SEED
    echo -ne "  -> Generating Standby Seed (Binary Clean)... "
    # Ensure binary integrity by redirecting stderr to dev/null
    $CONTAINER_MGR exec "${PRIMARY_NODE}" evoke seed standby "${S_FQDN}" "${CLUSTER_FQDN}" 1> "${SEED_FILE}" 2>/dev/null
    
    if [[ ! -s "${SEED_FILE}" ]]; then
        echo -e "${RED}FAILED to generate seed file!${NC}"
        continue
    fi
    echo -e "${GREEN}DONE${NC}"

    # 3. TRANSFER SEED TO STANDBY HOST
    echo -ne "  -> Transferring Seed to remote host... "
    scp -q -o StrictHostKeyChecking=no "${SEED_FILE}" "${SSH_USER}@${S_FQDN}:/tmp/"
    if [ $? -eq 0 ]; then echo -e "${GREEN}SUCCESS${NC}"; else echo -e "${RED}FAILED${NC}"; continue; fi

    # 4. REMOTE ACTIVATION (FIXED HOSTNAME VARIABLE)
    echo -e "  -> Triggering remote activation..."
    ssh -o StrictHostKeyChecking=no "${SSH_USER}@${S_FQDN}" "bash -s" << EOF
        set -e
        # Copy seed from host into the appliance container
        echo "     - Loading seed into container..."
        ${CONTAINER_MGR} cp /tmp/${S_NAME}_seed.tar.gz ${S_NAME}:/tmp/seed.tar.gz
        
        echo "     - Unpacking standby seed..."
        ${CONTAINER_MGR} exec ${S_NAME} evoke unpack seed /tmp/seed.tar.gz 2>&1
        
        echo "     - Configuring standby role..."
        ${CONTAINER_MGR} exec ${S_NAME} evoke configure standby 2>&1
        
        # Local cleanup on the remote host
        rm -f /tmp/${S_NAME}_seed.tar.gz
EOF

    if [ $? -eq 0 ]; then
        echo -e "  -> ${GREEN}SUCCESS:${NC} Standby ${S_NAME} is active."
    else
        echo -e "  -> ${RED}ERROR:${NC} Activation failed for ${S_NAME}."
    fi

    # Local cleanup on the Leader machine
    rm -f "${SEED_FILE}"
done

echo -e "\n${CYAN}========================================================${NC}"
echo -e "${GREEN} Step 06 Complete: Standby nodes provisioned.            ${NC}"
echo -e "${CYAN}========================================================${NC}"