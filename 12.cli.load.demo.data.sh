#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Loading Demo Policies and Seeding Secrets.

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

echo -e "${YELLOW}--- Starting Step 12: Loading Demo Policies and Data ---${NC}"

# --- Configuration ---
POLICY_DIR="./policies"
ROOT_POLICY="${POLICY_DIR}/root-policy.yaml"
DEMO_POLICY="${POLICY_DIR}/demo-data.yaml"

# --- Step 1: Pre-check Policy Files ---
echo -e "${BLUE}[INFO] Checking for required policy files...${NC}"
mkdir -p "$POLICY_DIR"

if [ ! -f "$ROOT_POLICY" ] || [ ! -f "$DEMO_POLICY" ]; then
    echo -e "${RED}[ERROR] Policy files missing in $POLICY_DIR${NC}"
    echo -e "${YELLOW}[TIP] Please ensure root-policy.yaml and demo-data.yaml are present in the directory.${NC}"
    exit 1
fi

# --- Step 2: Load Root Policy ---
echo -e "${BLUE}[INFO] Loading Root Policy into Conjur...${NC}"
conjur policy load -b root -f "$ROOT_POLICY"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Root policy loaded successfully.${NC}"
else
    echo -e "${RED}[ERROR] Failed to load Root policy. Verify CLI login status.${NC}"
    exit 1
fi

# --- Step 3: Load Demo Data Policy ---
echo -e "${BLUE}[INFO] Loading Demo Data Policy (Child of Root)...${NC}"
conjur policy load -b root -f "$DEMO_POLICY"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Demo data policy loaded successfully.${NC}"
else
    echo -e "${RED}[ERROR] Failed to load Demo data policy.${NC}"
    exit 1
fi

# --- Step 4: Set Variables (Secrets Seeding) ---
echo -e "${BLUE}[INFO] Seeding initial secrets into Conjur variables...${NC}"

# Using CONJUR_DOMAIN from 00.config.sh
conjur variable set -i test/host1/host -v "mysql.${CONJUR_DOMAIN}"
conjur variable set -i test/host1/user -v "cityapp"
conjur variable set -i test/host1/pass -v "Cyberark1"

echo -e "${GREEN}[SUCCESS] All demo variables have been initialized.${NC}"

# --- Step 5: Verification ---
echo -e "${CYAN}------------------------------------------------------------${NC}"
echo -e "${CYAN}   Final Verification: Retrieving a Secret via CLI          ${NC}"
echo -e "${CYAN}------------------------------------------------------------${NC}"
echo -ne "${BLUE}[INFO] Retrieving value for 'test/host1/user': ${NC}"
conjur variable get -i test/host1/user

echo -e "\n${CYAN}========================================================${NC}"
echo -e "${GREEN}  Step 12 Finished: Demo environment is ready for use.  ${NC}"
echo -e "${CYAN}========================================================${NC}"