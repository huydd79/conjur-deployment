#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 26, 2025
# Description: Global environment configuration.

# --- Configuration Status ---
READY=false

# --- Container Environment Setting ---
SUDO=
CONTAINER_MGR=podman

# --- Conjur Network Configuration ---
CONJUR_DOMAIN=poc.local
CONJUR_HTTPS_PORT=443

# --- Node Role Configuration ---
NODE_TYPE="primary" # "primary" or "standby" or "follower"
NODE_NAME=cjl100062

# --- Cluster Nodes Configuration ---
PRIMARY_NODE=cjl100062
PRIMARY_IP=172.16.100.62
STANDBY_NODES=("cjl100063" "cjl100064")
STANDBY_IPS=("172.16.100.63" "172.16.100.64")

# --- Follower Nodes Configuration ---
FOLLOWER_NODES=("cjf100066" "cjf100067")
FOLLOWER_IPS=("172.16.100.66" "172.16.100.67")

# --- Conjur Identity & Access Management ---
CONJUR_ADMIN_PW="ChangeMe123!!" 
CONJUR_ACCOUNT=POC 

# --- Versioning and Image Paths ---
UPLOAD_DIR=/opt/upload
CONJUR_APPLIANCE_FILE=conjur-appliance-Rls-v13.7.0.tar.gz
CONJUR_VERSION=13.7.0

# --- Configuration Header ---
# --- ANSI Color Codes for Professional Output ---
BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
echo -e "${CYAN}========================================================${NC}"
echo -e "${CYAN}      CyberArk Secrets Manager - Self-Hosted v${CONJUR_VERSION}${NC}"
echo -e "${CYAN}      Author: Huy Do (huy.do@cyberark.com)${NC}"
echo -e "${CYAN}========================================================${NC}"
echo -e "${BLUE}[INFO]${NC} Node Name    : ${NODE_NAME}"
if [[ "$NODE_TYPE" == "primary" ]]; then
    echo -e "${BLUE}[INFO]${NC} Standby Nodes : ${STANDBY_NODES[*]}"
fi