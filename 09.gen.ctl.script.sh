#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Generate a management script and link it to /usr/bin for global access.

# --- Source Configuration ---
if [ -f "./00.config.sh" ]; then
    source ./00.config.sh
else
    echo -e "\033[0;31m[ERROR] 00.config.sh not found!\033[0m"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 09: Generating Operations Tool & System Link ---${NC}"

OUTPUT_FILE="conjur-ctl.sh"
SYSTEM_LINK="/usr/bin/conjur-ctl"

# --- 1. Create the operation script content ---
cat << EOF > $OUTPUT_FILE
#!/bin/bash
# Description: Global control script for Conjur Appliance ($NODE_NAME)
# Generated on: $(date)

# ANSI Color Codes
BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

case "\$1" in
    start)
        echo -e "\${BLUE}[INFO]\${NC} Starting Conjur container: $NODE_NAME..."
        $SUDO $CONTAINER_MGR start $NODE_NAME
        ;;
    stop)
        echo -e "\${YELLOW}[INFO]\${NC} Stopping Conjur container: $NODE_NAME..."
        $SUDO $CONTAINER_MGR stop $NODE_NAME
        ;;
    restart)
        echo -e "\${BLUE}[INFO]\${NC} Restarting Conjur container: $NODE_NAME..."
        $SUDO $CONTAINER_MGR restart $NODE_NAME
        ;;
    status)
        echo -e "\${CYAN}========================================================\${NC}"
        echo -e "\${CYAN}            Conjur Node Status: $NODE_NAME              \${NC}"
        echo -e "\${CYAN}========================================================\${NC}"
        
        CONTAINER_STATUS=\$($SUDO $CONTAINER_MGR inspect $NODE_NAME --format '{{.State.Status}}' 2>/dev/null)
        if [ "\$CONTAINER_STATUS" == "running" ]; then
            echo -e " Container State : \${GREEN}RUNNING\${NC}"
            echo -e "--------------------------------------------------------"
            $SUDO $CONTAINER_MGR exec $NODE_NAME evoke status 2>/dev/null | grep -E "role|status|database"
        else
            echo -e " Container State : \${RED}\${CONTAINER_STATUS^^}\${NC}"
        fi
        echo -e "--------------------------------------------------------"
        $SUDO $CONTAINER_MGR ps -f name=$NODE_NAME
        ;;
    *)
        echo -e "Usage: conjur-ctl {start|stop|restart|status}"
        exit 1
        ;;
esac
EOF

# --- 2. Set Executive Permissions ---
chmod +x $OUTPUT_FILE

# --- 3. Link to /usr/bin for Global Execution ---
echo -e "${BLUE}[INFO]${NC} Linking script to ${SYSTEM_LINK}..."

# Remove existing link if it exists to avoid errors
if [ -L "$SYSTEM_LINK" ] || [ -f "$SYSTEM_LINK" ]; then
    $SUDO rm -f "$SYSTEM_LINK"
fi

# Create the symbolic link using the absolute path of the generated script
$SUDO ln -s "$(pwd)/$OUTPUT_FILE" "$SYSTEM_LINK"

# --- 4. Final Verification ---
if [ -L "$SYSTEM_LINK" ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Global command 'conjur-ctl' is now available."
    echo -e "${BLUE}[USAGE]${NC} You can now run these commands from anywhere:"
    echo -e "         conjur-ctl status"
    echo -e "         conjur-ctl stop"
    echo -e "         conjur-ctl start"
else
    echo -e "${RED}[ERROR]${NC} Failed to create system link in /usr/bin. Check sudo permissions."
    exit 1
fi

echo -e "${CYAN}========================================================${NC}"
echo -e "${GREEN} Step 09 Finished: Operations tool is globally ready.   ${NC}"
echo -e "${CYAN}========================================================${NC}"