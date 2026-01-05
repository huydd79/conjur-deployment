#!/bin/bash

# ==============================================================================
# CONJUR CLUSTER HEALTH REPORT - Replication Logic Fixed
# ==============================================================================

NODES=("cjl100062.poc.local" "cjl100063.poc.local" "cjl100064.poc.local" "cjf100066.poc.local" "cjf100067.poc.local")

# Escape Codes
R='\e[0m'; BOLD='\e[1m'; RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; MAGENTA='\e[35m'; CYAN='\e[36m'; DIM='\e[2m'

echo -e "${BOLD}CONJUR CLUSTER HEALTH STATUS REPORT${R}"
echo -e "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "------------------------------------------------------------------------------------------------------------------------------------------------------------"

printf "%-25s | %-10s | %-25s | %-12s | %-8s | %-8s | %-12s | %-8s | %-8s\n" \
       "Certificate Name" "Role" "Host IP / Name" "Container ID" "Services" "Database" "Replication" "Free Sp." "FIPS"
echo -e "------------------------------------------------------------------------------------------------------------------------------------------------------------"

# 1. Tìm Master và lấy dữ liệu replication của nó
MASTER_DATA=""
for n in "${NODES[@]}"; do
    raw=$(curl -s --connect-timeout 2 "http://$n:444/health")
    if [[ "$(echo "$raw" | jq -r '.role')" == "master" ]]; then
        MASTER_DATA="$raw"
        break
    fi
done

for host in "${NODES[@]}"; do
    h_json=$(curl -s --connect-timeout 2 "http://$host:444/health")
    i_json=$(curl -sk --connect-timeout 2 "https://$host/info")

    if [ -z "$h_json" ]; then
        printf "${RED}%-25s | %-10s | %-25s | %-12s | %-8s | %-8s | %-12s | %-8s | %-8s${R}\n" \
               "$host" "DOWN" "Offline" "---" "Error" "Error" "Error" "---" "---"
        continue
    fi

    # --- Trích xuất dữ liệu ---
    # Lấy hostname thực tế từ config
    host_id=$(echo "$i_json" | jq -r '.configuration.conjur.hostname // "Unknown"')
    # Lấy Certificate Name (dùng leader_name nếu có, không thì dùng hostname)
    cert_name=$(echo "$i_json" | jq -r '.configuration.conjur.cluster_leader // .configuration.conjur.hostname // "Unknown"')
    
    role=$(echo "$h_json" | jq -r '.role // "N/A"')
    cont_full=$(echo "$i_json" | jq -r '.container // ""')
    cont_short=$(echo "$cont_full" | cut -c1-12)
    fips=$(echo "$i_json" | jq -r '.fips_mode // "Unknown"')
    svc_ok=$(echo "$h_json" | jq -r '.ok')
    db_ok=$(echo "$h_json" | jq -r '.database.ok')
    kb=$(echo "$h_json" | jq -r '.database.free_space.main.kbytes // 0')
    free_sp="$(($kb / 1024 / 1024))GB"

    # --- Logic Replication ---
    repl_status="Unknown"
    repl_color=$DIM
    
    if [ "$role" == "master" ]; then
        repl_status="Leader"; repl_color=$CYAN
    else
        # QUAN TRỌNG: So khớp bằng Container ID thay vì Hostname
        if [ ! -z "$MASTER_DATA" ] && [ ! -z "$cont_full" ]; then
            state=$(echo "$MASTER_DATA" | jq -r ".database.replication_status.pg_stat_replication[] | select(.application_name | contains(\"$cont_full\")) | .sync_state" | head -n 1)
            
            if [ "$state" == "sync" ]; then 
                repl_status="Sync"; repl_color=$GREEN
            elif [ "$state" == "async" ] || [ "$state" == "potential" ]; then 
                repl_status="Async"; repl_color=$YELLOW
            else
                # Check nếu bản thân node báo đang streaming
                streaming=$(echo "$h_json" | jq -r '.database.replication_status.streaming // false')
                if [ "$streaming" == "true" ]; then repl_status="Async"; repl_color=$YELLOW; fi
            fi
        fi
        
        # Kiểm tra Lag
        lag=$(echo "$h_json" | jq -r '.database.replication_status.replication_lag_seconds // 0')
        [[ "$lag" -gt 0 ]] && repl_status="${repl_status}!"
    fi

    # --- PRINT ROW ---
    printf "%-25s | " "$cert_name"
    
    # Role color (Master=Blue, Standby=Yellow, Follower=Magenta)
    if [ "$role" == "master" ]; then printf "${BLUE}"; elif [ "$role" == "follower" ]; then printf "${MAGENTA}"; else printf "${YELLOW}"; fi
    printf "%-10s${R} | " "${role^}"
    
    printf "%-25s | " "$host_id"
    printf "%-12s | " "$cont_short"
    
    # Services & DB
    if [ "$svc_ok" == "true" ]; then printf "${GREEN}%-8s${R} | " "Good"; else printf "${RED}%-8s${R} | " "Bad"; fi
    if [ "$db_ok" == "true" ]; then printf "${GREEN}%-8s${R} | " "Good"; else printf "${RED}%-8s${R} | " "Bad"; fi

    printf "${repl_color}%-12s${R} | " "$repl_status"
    printf "%-8s | " "$free_sp"
    
    [[ "$fips" == "enabled" ]] && printf "${GREEN}" || printf "${DIM}"
    printf "%-8s${R}\n" "${fips^}"
done
echo -e "------------------------------------------------------------------------------------------------------------------------------------------------------------"