#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 30, 2025
# Description: Step 09 - Activate Sync Replication and Verify Cluster Health (v13.7).

if [ -f "./00.config.sh" ]; then source ./00.config.sh; else exit 1; fi

# --- 1. Guard Clause ---
if [[ "$NODE_TYPE" != "primary" ]]; then
    echo -e "${RED}[ERROR] This script must only be executed on the PRIMARY (Leader) node.${NC}"
    exit 1
fi

echo -e "${YELLOW}--- Phase 1: Activating Synchronous Replication ---${NC}"

# According to v13.7 documentation: 'evoke replication sync start'
# We use --force to bypass the 2-standby recommendation check for lab environments.
echo -e "${BLUE}[INFO]${NC} Executing: evoke replication sync start --force"
$SUDO $CONTAINER_MGR exec "$NODE_NAME" evoke replication sync start --force

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS] Synchronous mode activated.${NC}"
else
    echo -e "${RED}[ERROR] Failed to activate sync mode. Ensure Standbys are connected.${NC}"
    exit 1
fi

# Give the cluster a moment to stabilize replication threads
echo -e "${BLUE}[INFO]${NC} Waiting 5 seconds for replication stabilization..."
sleep 5

echo -e "${YELLOW}--- Phase 2: Verifying Cluster Health & Sync State ---${NC}"

# 2. Fetch raw health data from the API
RAW_HEALTH=$(curl -k -s "https://localhost:$CONJUR_HTTPS_PORT/health")

if [ -z "$RAW_HEALTH" ]; then
    echo -e "${RED}[ERROR] Could not reach Conjur Health API.${NC}"
    exit 1
fi

# 3. Extract Core Identity and Status
ROLE=$(echo "$RAW_HEALTH" | jq -r '.database.replication_status.role // .database.role')
OK_STATUS=$(echo "$RAW_HEALTH" | jq -r '.ok')

echo -e "--------------------------------------------------------"
echo -e "  Node Name : ${NODE_NAME}"
echo -e "  API Role  : ${CYAN}${ROLE^^}${NC}"
echo -e "  Health    : $([[ "$OK_STATUS" == "true" ]] && echo -e "${GREEN}OK" || echo -e "${RED}ERROR")${NC}"
echo -e "--------------------------------------------------------"

# 4. Display Replication Statistics
echo -e "${CYAN}[REPLICATION DASHBOARD]${NC}"
REPLICATION_JSON=$(echo "$RAW_HEALTH" | jq '.database.replication_status.pg_stat_replication')

if [[ "$REPLICATION_JSON" == "null" || "$REPLICATION_JSON" == "[]" ]]; then
    echo -e "${YELLOW}[WARN] No Standby nodes detected.${NC}"
    echo -e "Tip: Ensure Script 08 (with 'sync enable') was run on Standbys."
else
    # Professional Table Header
    printf "${WHITE}%-20s %-15s %-15s %-10s${NC}\n" "HOSTNAME" "IP ADDRESS" "DB STATE" "SYNC MODE"
    echo "--------------------------------------------------------"
    
    echo "$REPLICATION_JSON" | jq -c '.[]' | while read -r item; do
        NAME=$(echo "$item" | jq -r '.application_name')
        IP=$(echo "$item" | jq -r '.client_addr')
        STATE=$(echo "$item" | jq -r '.state')
        SYNC=$(echo "$item" | jq -r '.sync_state')
        
        # Color coding: Green for streaming/sync, Yellow for others
        COLOR=$GREEN
        [[ "$SYNC" != "sync" && "$SYNC" != "quorum" ]] && COLOR=$YELLOW
        
        printf "${COLOR}%-20s %-15s %-15s %-10s${NC}\n" "$NAME" "$IP" "$STATE" "$SYNC"
    done
fi

echo -e "========================================================"
echo -e "${GREEN} Deployment and Synchronization Check Complete.         ${NC}"
echo -e "========================================================"