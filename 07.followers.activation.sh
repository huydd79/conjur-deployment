#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 30, 2025
# Description: Step 12 - Activate Followers using Leader's Internal CA.
# Strategy: Standard seed generation, DB whitelisting, and robust activation.

if [ -f "./00.config.sh" ]; then source ./00.config.sh; else exit 1; fi

# --- Guard Clause ---
# Ensure this script only runs on the Primary (Leader) node
if [[ "$NODE_TYPE" != "primary" ]]; then
    echo -e "${RED}[ERROR] This script must only be executed on the PRIMARY node.${NC}"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 12: Follower Activation (Internal CA Mode) ---${NC}"

SSH_USER="root"
CLUSTER_FQDN=$CONJUR_LEADER_FQDN

# ==========================================================
# PRE-CHECK: API (443) & POSTGRES (5432)
# ==========================================================
echo -e "${BLUE}[PRE-CHECK]${NC} Verifying Cluster Connectivity ($CLUSTER_FQDN)..."

# 1. Check HTTPS Health (API Layer)
echo -ne "  -> API Health (444): "
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

# 3. Check Postgres Port (Replication Layer)
echo -ne "  -> Audit Stream Port (1999): "
# nc -z: scan mode, -w 3: timeout 3 seconds
nc -z -w 3 "$CLUSTER_FQDN" 1999 > /dev/null 2>&1
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
# === DONE PRECHECK ==============================================

for i in "${!FOLLOWER_NODES[@]}"; do
    F_NAME="${FOLLOWER_NODES[$i]}"
    F_FQDN="${F_NAME}.${CONJUR_DOMAIN}"
    SEED_FILE="/tmp/${F_NAME}_seed.tar.gz"

    echo -e "\n${BLUE}========================================================${NC}"
    echo -e " TARGET FOLLOWER: ${F_FQDN}"
    echo -e "${BLUE}========================================================${NC}"

    # 1. CHECK READINESS & ROLE
    echo -ne "  -> Checking readiness & node role... "
    # Verify SSH connectivity and ensure the remote appliance is in 'blank' state
    if ! ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 "${SSH_USER}@${F_FQDN}" "$CONTAINER_MGR exec ${CONTAINER_NAME} evoke role show" | grep -q "blank"; then
        echo -e "${RED}NOT BLANK OR UNREACHABLE${NC} (Skipping)"
        continue
    fi
    echo -e "${GREEN}READY${NC}"

    # 2. GENERATE SEED (Using Master Internal CA)
    echo -ne "  -> Generating Seed ... "
    # Redirect stderr (2) to /dev/null to prevent WARN logs from corrupting the binary tarball (stdout)
    $CONTAINER_MGR exec "${CONTAINER_NAME}" evoke seed follower --replication-set full "${F_FQDN}" "${CLUSTER_FQDN}" 1> "${SEED_FILE}"
    
    if [[ ! -s "${SEED_FILE}" ]]; then
        echo -e "${RED}FAILED${NC}"
        continue
    fi
    echo -e "${GREEN}DONE${NC}"

    # 3. TRANSFER SEED TO FOLLOWER
    echo -ne "  -> Transferring Seed... "
    scp -q -o StrictHostKeyChecking=no "${SEED_FILE}" "${SSH_USER}@${F_FQDN}:/tmp/"
    echo -e "${GREEN}SUCCESS${NC}"

    # 4. ACTIVATE FOLLOWER
    echo -e "  -> Triggering remote activation (Unpack & Configure)..."
    ssh -o StrictHostKeyChecking=no "${SSH_USER}@${F_FQDN}" "bash -s" << EOF
        set -e
        # Copy seed from host into the appliance container
        ${CONTAINER_MGR} cp /tmp/${F_NAME}_seed.tar.gz ${CONTAINER_NAME}:/tmp/seed.tar.gz
        
        echo "     - Unpacking seed identity..."
        ${CONTAINER_MGR} exec ${CONTAINER_NAME} evoke unpack seed /tmp/seed.tar.gz
        
        echo "     - Configuring follower (Connecting to $CLUSTER_FQDN)..."
        # Note: --force-new-id may be required if reconfiguring a previously used node
        ${CONTAINER_MGR} exec ${CONTAINER_NAME} evoke configure follower
        
        # Cleanup temporary seed on remote host
        rm -f /tmp/${F_NAME}_seed.tar.gz
EOF

    if [ $? -eq 0 ]; then
        echo -e "  -> ${GREEN}SUCCESS:${NC} Follower ${F_NAME} is now active and replicating."
    else
        echo -e "  -> ${RED}ERROR:${NC} Activation failed. Check Follower container logs."
    fi

    # Cleanup local seed file on Leader
    rm -f "${SEED_FILE}"
done

echo -e "\n${CYAN}========================================================${NC}"
echo -e "${GREEN} Step 12 Complete: Followers successfully provisioned.   ${NC}"
echo -e "${CYAN}========================================================${NC}"