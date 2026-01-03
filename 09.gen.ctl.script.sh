#!/bin/bash
# Author: Huy Do (huy.do@cyberark.com)
# Date: December 31, 2025
# Description: Generate an advanced management script with Node Role Detection.

# --- Source Configuration ---
if [ -f "./00.config.sh" ]; then
    source ./00.config.sh
else
    echo -e "\033[0;31m[ERROR] 00.config.sh not found!\033[0m"
    exit 1
fi

echo -e "${YELLOW}--- Starting Step 09: Generating Advanced Operations Tool ---${NC}"

OUTPUT_FILE="conjur-ctl.sh"
SYSTEM_LINK="/usr/bin/conjur-ctl"

# --- 1. Create the operation script content ---
cat << EOF > $OUTPUT_FILE
#!/bin/bash
# Description: Global control script for Conjur Appliance ($NODE_NAME)
# Generated on: $(date)

# ANSI Color Codes
BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

case "\$1" in
    start)
        echo -e "\${BLUE}[INFO]\${NC} Starting Conjur container: $CONTAINER_NAME..."
        $SUDO $CONTAINER_MGR start $CONTAINER_NAME
        ;;
    stop)
        echo -e "\${YELLOW}[INFO]\${NC} Stopping Conjur container: $CONTAINER_NAME..."
        $SUDO $CONTAINER_MGR stop $NCONTAINER_NAME
        ;;
    restart)
        echo -e "\${BLUE}[INFO]\${NC} Restarting Conjur container: $CONTAINER_NAME..."
        $SUDO $CONTAINER_MGR restart $CONTAINER_NAME
        ;;
    status)
        echo -e "\${CYAN}========================================================\${NC}"
        echo -e "\${CYAN}            Conjur Node Status: $NODE_NAME              \${NC}"
        echo -e "\${CYAN}========================================================\${NC}"
        
        # Check Container Runtime Status
        CONTAINER_STATUS=\$($SUDO $CONTAINER_MGR inspect $CONTAINER_NAME --format '{{.State.Status}}' 2>/dev/null)
        
        if [ "\$CONTAINER_STATUS" == "running" ]; then
            echo -e " Container State : \${GREEN}RUNNING\${NC}"
            
            # Detect Internal Conjur Role
            RAW_ROLE=\$($SUDO $CONTAINER_MGR exec $CONTAINER_NAME evoke role show 2>/dev/null)
            
            case "\$RAW_ROLE" in
                master)
                    FRIENDLY_ROLE="\${GREEN}\${BOLD}PRIMARY LEADER\${NC}"
                    ;;
                standby)
                    FRIENDLY_ROLE="\${BLUE}\${BOLD}STANDBY NODE\${NC}"
                    ;;
                follower)
                    FRIENDLY_ROLE="\${CYAN}\${BOLD}FOLLOWER NODE\${NC}"
                    ;;
                blank)
                    FRIENDLY_ROLE="\${YELLOW}UNCONFIGURED (BLANK)\${NC}"
                    ;;
                *)
                    FRIENDLY_ROLE="\${RED}UNKNOWN\${NC} (\$RAW_ROLE)"
                    ;;
            esac
            
            echo -e " Conjur Role     : \$FRIENDLY_ROLE"
            echo -e "--------------------------------------------------------"
            
            # Display core service status from evoke
            $SUDO $CONTAINER_MGR exec $CONTAINER_NAME evoke status 2>/dev/null | grep -E "status|database"
        else
            echo -e " Container State : \${RED}\${CONTAINER_STATUS^^}\${NC}"
            echo -e " Conjur Role     : \${RED}OFFLINE\${NC}"
        fi
        echo -e "--------------------------------------------------------"
        $SUDO $CONTAINER_MGR ps -f name=$CONTAINER_NAME
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

if [ -L "$SYSTEM_LINK" ] || [ -f "$SYSTEM_LINK" ]; then
    $SUDO rm -f "$SYSTEM_LINK"
fi

# Create symbolic link using the absolute path of the generated script
$SUDO ln -s "$(pwd)/$OUTPUT_FILE" "$SYSTEM_LINK"

# --- 4. Final Verification and Display Usage ---
if [ -L "$SYSTEM_LINK" ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Global command 'conjur-ctl' is now available."
    echo -e "${BLUE}[USAGE]${NC} You can now run these commands from anywhere:"
    echo -e "         ${BOLD}conjur-ctl status${NC}  -> Check container & cluster role"
    echo -e "         ${BOLD}conjur-ctl stop${NC}    -> Stop the Conjur service"
    echo -e "         ${BOLD}conjur-ctl start${NC}   -> Start the Conjur service"
    echo -e "         ${BOLD}conjur-ctl restart${NC} -> Restart the Conjur service"
else
    echo -e "${RED}[ERROR]${NC} Failed to create system link in /usr/bin. Check sudo permissions."
    exit 1
fi

echo -e "${CYAN}========================================================${NC}"
echo -e "${GREEN} Step 09 Finished: Operations tool is globally ready.   ${NC}"
echo -e "${CYAN}========================================================${NC}"