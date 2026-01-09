#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Cluster Policy Generation and Auto-Failover Enrollment for Leader node.

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

# --- Local Variables ---
mkdir -p tmp
POLICY_FILE="tmp/cluster-failover-policy.yml"
LEADER_FQDN=$PRIMARY_NODE.${CONJUR_DOMAIN}

echo -e "${YELLOW}--- Starting Step 12: Cluster Auto-Failover Configuration ---${NC}"

# --- 1. Verify Node Role ---
echo -ne "${CYAN}[CHECK]${NC} Verifying node role for Auto-failover... "
if [[ "$NODE_TYPE" == "primary" ]]; then
    echo -e "${GREEN}Primary Node Detected${NC}"
else
    echo -e "${RED}Invalid Node Type ($NODE_TYPE)${NC}"
    echo -e "${YELLOW}[TIP] This script must be executed on the Primary (Leader) node only.${NC}"
    exit 1
fi

# --- 2. Generate Cluster Policy YAML ---
echo -e "${CYAN}[PROCESS]${NC} Generating Cluster Policy: ${POLICY_FILE}..."

# Start creating the policy file
cat <<EOF > $POLICY_FILE
---
- !policy
  id: conjur
  body:
    - !policy
        id: cluster/$CLUSTER_NAME
        annotations:
          ttl: $CLUSTER_TTL
        body:
        - !layer
        - &hosts
          - !host
            id: $LEADER_FQDN
EOF

# Dynamically add Standby Nodes from the array in 00.config.sh
for S_NAME in "${STANDBY_NODES[@]}"; do
    echo "          - !host" >> $POLICY_FILE
    echo "            id: ${S_NAME}.${CONJUR_DOMAIN}" >> $POLICY_FILE
done

# Finalize the Policy structure
cat <<EOF >> $POLICY_FILE
        - !grant
          role: !layer
          member: *hosts
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Policy file generated with CLUSTER_NAME: ${CLUSTER_NAME}."
else
    echo -e "${RED}[ERROR]${NC} Failed to create policy file."
    exit 1
fi

# --- 3. Load Policy via Conjur CLI ---
echo -e "${CYAN}[PROCESS]${NC} Loading cluster policy to Conjur root..."
# Assumes Conjur CLI is already authenticated on the host
conjur policy load -b root -f $POLICY_FILE

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Cluster policy applied successfully."
else
    echo -e "${RED}[ERROR]${NC} Failed to load policy. Ensure Conjur CLI is authenticated.${NC}"
    exit 1
fi

# --- 4. Enroll Primary Node into Cluster ---
echo -e "${CYAN}[PROCESS]${NC} Enrolling node ${LEADER_FQDN} as Cluster Leader..."

$SUDO $CONTAINER_MGR exec $CONTAINER_NAME evoke cluster enroll -n $LEADER_FQDN $CLUSTER_NAME

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Node enrolled as Leader successfully."
else
    echo -e "${RED}[ERROR]${NC} Enrollment failed.${NC}"
    exit 1
fi

# --- 5. Health Verification ---
echo -e "${CYAN}[CHECK]${NC} Verifying Cluster Health via Port 444..."
sleep 5
# Using the port 444 health check method as previously discussed
HEALTH_CHECK=$(curl -s http://localhost:444/health)
CLUSTER_STATUS=$(echo $HEALTH_CHECK | jq -r '.status')

if [[ "$CLUSTER_STATUS" == "OK" ]]; then
    echo -e "${GREEN}[OK]${NC} Cluster Status: RUNNING"
    echo -e "${BLUE}[INFO]${NC} Role: Master (Primary)"
else
    echo -e "${RED}[WARNING]${NC} Cluster status is $CLUSTER_STATUS. Please check logs for replication errors."
    echo -e "${YELLOW}[DEBUG]${NC} Raw Health: $HEALTH_CHECK"
fi

# --- Footer & Instructions for Standby Nodes ---
echo -e "${CYAN}========================================================${NC}"
echo -e "${GREEN} Step 12 Finished: Leader Auto-Failover is READY.      ${NC}"
echo -e "${CYAN}========================================================${NC}"
echo -e "${YELLOW}[NEXT STEPS] Execute enrollment on Standby Nodes:${NC}"
for S_NAME in "${STANDBY_NODES[@]}"; do
    S_FQDN="${S_NAME}.${CONJUR_DOMAIN}"
    echo -e "  - On node ${S_NAME}: ${CYAN}evoke cluster enroll -n $S_FQDN -m $LEADER_FQDN $CLUSTER_NAME${NC}"
done
echo -e "${CYAN}========================================================${NC}"
