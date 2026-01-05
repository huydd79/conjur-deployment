#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Install and Initialize Conjur CLI (Strict Documentation Sync).

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

echo -e "${YELLOW}--- Starting Step 11: Install & Init Conjur CLI ---${NC}"

# --- Step 1: Detect OS and Define Package Path ---
if [ -f /etc/debian_version ]; then
    PKG_TYPE="DEB"
    PKG_PATH=$(ls "${UPLOAD_DIR}"/conjur-cli_*.deb 2>/dev/null | head -n 1)
elif [ -f /etc/redhat-release ] || [ -f /etc/system-release ]; then
    PKG_TYPE="RPM"
    PKG_PATH=$(ls "${UPLOAD_DIR}"/conjur-cli_*.rpm 2>/dev/null | head -n 1)
else
    echo -e "${RED}[ERROR] Unsupported OS for native package installation.${NC}"
    exit 1
fi

# --- Step 2: Strict Package Existence Check ---
if [[ -z "$PKG_PATH" || ! -f "$PKG_PATH" ]]; then
    echo -e "${RED}[FATAL ERROR] CLI Package not found in $UPLOAD_DIR${NC}"
    echo -e "${YELLOW}[TIP] Please upload the .deb or .rpm Conjur CLI package to $UPLOAD_DIR${NC}"
    exit 1
fi

# --- Step 3: Install Package ---
echo -e "${BLUE}[INFO] Installing $PKG_TYPE package from: $PKG_PATH...${NC}"
if [ "$PKG_TYPE" == "DEB" ]; then
    $SUDO dpkg -i "$PKG_PATH" || $SUDO apt-get install -f -y
else
    $SUDO rpm -ivh "$PKG_PATH" --force
fi

# --- Step 4: Host Resolution for CLI ---
# Ensuring the CLI can resolve the cluster DNS locally
CONJUR_FQDN=$CONJUR_LEADER_FQDN
echo -e "${BLUE}[INFO] Mapping ${CONJUR_FQDN} in /etc/hosts...${NC}"
$SUDO sed -i "/${CONJUR_FQDN}/d" /etc/hosts
echo "${LEADER_VIP} ${CONJUR_FQDN}" | $SUDO tee -a /etc/hosts > /dev/null

# --- Step 5: Initialize CLI ---
echo -e "${BLUE}[INFO] Initializing CLI with official parameters...${NC}"

CONJUR_URL="https://${CONJUR_FQDN}:${CONJUR_HTTPS_PORT}"
CA_CERT_PATH="./certs/ca-chain.pem"

if [ -f "$CA_CERT_PATH" ]; then
    echo -e "${GREEN}[OK]${NC} Using provided CA chain: $CA_CERT_PATH"
    conjur init -u "$CONJUR_URL" -a "$CONJUR_ACCOUNT" -c "$CA_CERT_PATH" --force
else
    echo -e "${YELLOW}[WARN] CA cert not found. Falling back to self-signed/insecure...${NC}"
    conjur init -u "$CONJUR_URL" -a "$CONJUR_ACCOUNT" --self-signed --force
fi

# --- Step 6: Login ---
echo -e "${CYAN}------------------------------------------------------------${NC}"
echo -e "${YELLOW}ACTION: Login to Conjur as admin${NC}"
echo -e "${CYAN}------------------------------------------------------------${NC}"
# Note: This will prompt for the admin password defined in 00.config.sh
conjur login -i admin

# --- Step 7: Verification ---
echo -e "${BLUE}[INFO] Verifying session identity:${NC}"
conjur whoami

echo -e "${CYAN}========================================================${NC}"
echo -e "${GREEN} Step 11 Finished: Conjur CLI is ready for use.         ${NC}"
echo -e "${CYAN}========================================================${NC}"