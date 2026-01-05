#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Step 14 - Advanced Cluster Health & Failover Readiness Dashboard.
# Strategy: Parses cluster-level degradation and replication sync states.

# --- Source Configuration ---
if [ -f "./00.config.sh" ]; then source ./00.config.sh; else exit 1; fi

# --- Guard Clause ---
if [[ "$NODE_TYPE" != "primary" ]]; then
    echo -e "${RED}[ERROR] This script must only be executed on the PRIMARY node.${NC}"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 14: Auto-Failover Status Dashboard ---${NC}"

SSH_USER="root"

# Function to parse and display detailed node status
display_node_status() {
    local NODE_FQDN=$1
    local JSON_DATA=$2

    if [[ -z "$JSON_DATA" || "$JSON_DATA" == "null" ]]; then
        printf "  - ${CYAN}%-25s${NC} | ${RED}%-12s${NC} | %-8s | %-8s | %-12s\n" "$NODE_FQDN" "OFFLINE" "N/A" "N/A" "N/A"
        return
    fi

    # Extracting core values
    local STATE=$(echo "$JSON_DATA" | jq -r '.cluster.status // "unknown"')
    local ROLE=$(echo "$JSON_DATA" | jq -r '.role // "unknown"')
    
    # FIXED: Extracting Degraded status from multiple possible paths
    local DEGRADED=$(echo "$JSON_DATA" | jq -r '.cluster.degraded // .degraded // "unknown"')
    
    # Identify Sync Mode
    local SYNC_MODE="Async"
    if [[ "$ROLE" == "master" ]]; then
        SYNC_MODE="LEADER"
    else
        # Check if this standby is the synchronous one
        # Logic: In 13.x, standby nodes show streaming status
        local IS_STREAMING=$(echo "$JSON_DATA" | jq -r '.database.replication_status.streaming // "false"')
        [[ "$IS_STREAMING" == "true" ]] && SYNC_MODE="Replicating" || SYNC_MODE="Lagging"
    fi

    # Formatting DEGRADED output with colors
    local DEG_COLOR=$GREEN
    [[ "$DEGRADED" == "true" ]] && DEG_COLOR=$RED
    [[ "$DEGRADED" == "unknown" ]] && DEG_COLOR=$YELLOW

    # Formatting STATE output
    local STATE_COLOR=$RED
    [[ "$STATE" == "running" || "$STATE" == "standing_by" ]] && STATE_COLOR=$GREEN

    printf "  - ${CYAN}%-25s${NC} | ${STATE_COLOR}%-12s${NC} | %-8s | ${DEG_COLOR}%-8s${NC} | %-12s\n" \
           "$NODE_FQDN" "$STATE" "$ROLE" "$DEGRADED" "$SYNC_MODE"
}

echo -e "${BLUE}========================================================================================${NC}"
printf "  %-28s | %-12s | %-8s | %-8s | %-12s\n" "NODE FQDN" "STATE" "ROLE" "DEGRADED" "SYNC MODE"
echo -e "${BLUE}========================================================================================${NC}"

# --- 1. LOCAL CHECK (LEADER) ---
LOCAL_JSON=$(curl -s http://localhost:444/health)
display_node_status "$CONJUR_LEADER_FQDN" "$LOCAL_JSON"

# --- 2. REMOTE CHECK (STANDBYS) ---
for S_NAME in "${STANDBY_NODES[@]}"; do
    S_FQDN="${S_NAME}.${CONJUR_DOMAIN}"
    REMOTE_JSON=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 "${SSH_USER}@${S_FQDN}" "curl -s http://localhost:444/health" 2>/dev/null)
    display_node_status "$S_FQDN" "$REMOTE_JSON"
done

echo -e "${BLUE}========================================================================================${NC}"

# --- 3. AUTO-FAILOVER ANALYSIS ---
echo -e "\n${CYAN}[AUTO-FAILOVER ANALYSIS]${NC}"
echo -e "  -> Cluster TTL Configuration: ${YELLOW}${CLUSTER_TTL} seconds${NC}"

# Logic to find the Synchronous standby candidate for failover
SYNC_CANDIDATE=$(echo "$LOCAL_JSON" | jq -r '.database.replication_status.pg_stat_replication[] | select(.sync_state=="sync") | .usename' | head -n 1)

if [[ -n "$SYNC_CANDIDATE" ]]; then
    echo -e "  -> Failover Candidate (Sync): ${GREEN}${SYNC_CANDIDATE}${NC}"
    echo -e "  -> Failover Status          : ${GREEN}READY${NC} (Zero data loss guaranteed)"
else
    echo -e "  -> Failover Candidate (Sync): ${RED}None Found${NC}"
    echo -e "  -> Failover Status          : ${YELLOW}DEGRADED${NC} (Will failover with potential data lag)"
fi

echo -e "\n${CYAN}========================================================${NC}"
echo -e "${GREEN} Step 14 Complete: Failover Readiness Checked.           ${NC}"
echo -e "${CYAN}========================================================${NC}"