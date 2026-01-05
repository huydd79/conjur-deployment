#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Automatically granting POC permissions for Vault Synced data.

# --- Source Configuration ---
if [ -f "./00.config.sh" ]; then
    source ./00.config.sh
else
    echo -e "\033[0;31m[ERROR] 00.config.sh not found!\033[0m"
    exit 1
fi

if [[ "$READY" != true ]]; then
    echo -e "${RED}[ERROR] Configuration is not ready. Set READY=true in 00.config.sh${NC}"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 22: Granting POC Permissions for Vault Sync Data ---${NC}"

# --- Configuration ---
POLICY_DIR="./policies"
PERMISSION_POLICY="${POLICY_DIR}/poc-permission.yaml"
SEARCH_PATTERN="delegation/consumers"

# --- Step 1: Search for Synchronizer Groups ---
echo -e "${BLUE}[INFO] Searching for Vault Synchronizer groups in Conjur...${NC}"

# Finding groups that match the synchronizer delegation pattern
GROUPS_FOUND=$(conjur list -k group | grep "$SEARCH_PATTERN")

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}[OK] Synchronizer group(s) found.${NC}"
    
    mkdir -p "$POLICY_DIR"
    echo "# POC Permission Policy - Auto-generated" > "$PERMISSION_POLICY"

    # --- Step 2: Generate Policy Dynamically ---
    # This loop identifies synced Safe groups and grants them to demo roles
    for line in $GROUPS_FOUND; do
        # Extracting the group ID from the JSON/String output
        CLEAN_GROUP=$(echo "$line" | sed 's/.*group:\([^"]*\).*/\1/')
        
        echo -e "${BLUE}[INFO] Granting access to synced group: ${NC}$CLEAN_GROUP"
        
        cat <<EOF >> "$PERMISSION_POLICY"
- !grant
  role: !group $CLEAN_GROUP
  member:
    - !group test/test_users
    - !layer test/test_hosts
EOF
    done

    # --- Step 3: Load the Generated Policy ---
    echo -e "${BLUE}[INFO] Loading generated permission policy into Conjur...${NC}"
    conjur policy load -b root -f "$PERMISSION_POLICY"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS] Permissions granted successfully.${NC}"
    else
        echo -e "${RED}[ERROR] Failed to load the permission policy.${NC}"
        exit 1
    fi
else
    echo -e "${RED}[WARNING] Vault data not found (No group matching '$SEARCH_PATTERN').${NC}"
    echo -e "${YELLOW}[TIP] Ensure your Vault Synchronizer is running and has successfully synced a Safe/LOB.${NC}"
fi

# --- Final Status Banner ---
echo -e "${CYAN}========================================================${NC}"
echo -e "${GREEN}  Step 22 Finished: POC Permission setup complete.      ${NC}"
echo -e "${CYAN}========================================================${NC}"