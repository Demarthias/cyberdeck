#!/bin/bash
# Automated Response Playbooks - TIER 2
# Rule-based automated actions: if X happens, do Y

DAEMON_NAME="playbooks"
CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"

# Source shared library
source "${CYBERDECK_HOME}/lib/common.sh"

# Initialize
write_pid "$DAEMON_NAME"
trap "daemon_cleanup \"$DAEMON_NAME\"" EXIT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 130" INT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 143" TERM

log $LOG_INFO "$DAEMON_NAME" "Playbooks engine starting..."

# === Playbook Configuration ===

PLAYBOOKS_DIR="${CYBERDECK_HOME}/playbooks"
mkdir -p "$PLAYBOOKS_DIR"

# Load playbooks
PLAYBOOKS_FILE="${PLAYBOOKS_DIR}/rules.conf"

# Create default playbooks if not exists
if [[ ! -f "$PLAYBOOKS_FILE" ]]; then
    cat > "$PLAYBOOKS_FILE" <<'EOF'
# Cyberdeck Automated Response Playbooks
# Format: TRIGGER|CONDITION|ACTION|PARAMETERS

# Example playbooks:
# port_scan|ports_gt_10|block_ip|
# country|eq_CN|increase_score|5
# honeypot_hit|service_eq_ssh|deploy_honeypot|2223
# brute_force|attempts_gt_5|freeze_process|
# malware_detected|confidence_gt_80|capture_memory|

# Active playbooks:
port_scan|ports_gt_5|increase_score|3
port_scan|ports_gt_10|block_ip|
ssh_honeypot|attempts_gt_3|block_ip|
wordpress_hit|always|increase_score|4
tor_exit|always|tag|tor_user
high_frequency|connections_gt_50|block_ip|
credential_stuffing|attempts_gt_5|capture_credentials|
EOF
    log $LOG_INFO "$DAEMON_NAME" "Created default playbooks file"
fi

# === Playbook Functions ===

# Check if condition matches
check_condition() {
    local condition=$1
    local value=$2
    
    case $condition in
        always)
            return 0
            ;;
        ports_gt_*)
            local threshold=${condition#ports_gt_}
            [[ $value -gt $threshold ]] && return 0
            ;;
        connections_gt_*)
            local threshold=${condition#connections_gt_}
            [[ $value -gt $threshold ]] && return 0
            ;;
        attempts_gt_*)
            local threshold=${condition#attempts_gt_}
            [[ $value -gt $threshold ]] && return 0
            ;;
        score_gt_*)
            local threshold=${condition#score_gt_}
            [[ $value -gt $threshold ]] && return 0
            ;;
        eq_*)
            local expected=${condition#eq_}
            [[ "$value" == "$expected" ]] && return 0
            ;;
        contains_*)
            local pattern=${condition#contains_}
            [[ "$value" =~ $pattern ]] && return 0
            ;;
    esac
    
    return 1
}

# Execute action
execute_action() {
    local action=$1
    local ip=$2
    local params=$3
    
    log $LOG_INFO "$DAEMON_NAME" "Executing action: $action for $ip (params: $params)"
    
    case $action in
        block_ip)
            # Send block command
            sqlite3 "${DB_PATH}" "UPDATE threats SET blocked=1 WHERE ip='$ip';" 2>/dev/null
            db_record_alert "$ip" "RED" "Playbook action: blocked by automated rule"
            log $LOG_WARN "$DAEMON_NAME" "Auto-blocked $ip via playbook"
            ;;
            
        increase_score)
            local boost=${params:-5}
            db_record_threat "$ip" "$boost"
            log $LOG_INFO "$DAEMON_NAME" "Increased threat score for $ip by $boost"
            ;;
            
        deploy_honeypot)
            local port=${params:-2224}
            log $LOG_INFO "$DAEMON_NAME" "Would deploy honeypot on port $port for $ip"
            # This would trigger honeypot daemon to start new service
            ;;
            
        freeze_process)
            # Find and freeze processes connected to this IP
            log $LOG_INFO "$DAEMON_NAME" "Freezing processes connected to $ip"
            # Implementation would use SIGSTOP on matched PIDs
            ;;
            
        capture_credentials)
            # Log credential capture event
            db_record_alert "$ip" "YELLOW" "Credential stuffing detected - capturing attempts"
            log $LOG_WARN "$DAEMON_NAME" "Credential stuffing from $ip"
            ;;
            
        tag)
            local tag=${params:-suspicious}
            local safe_tag safe_ip
            safe_tag=$(sanitize_sql "$tag")
            safe_ip=$(sanitize_sql "$ip")
            sqlite3 "${DB_PATH}" \
                "UPDATE threats SET notes='$safe_tag' WHERE ip='$safe_ip';" 2>/dev/null
            log $LOG_INFO "$DAEMON_NAME" "Tagged $ip as $tag"
            ;;
            
        alert_webhook)
            # Send high-priority alert
            db_record_alert "$ip" "RED" "Playbook triggered webhook: $params"
            ;;
            
        capture_memory)
            log $LOG_INFO "$DAEMON_NAME" "Would capture memory dump for processes from $ip"
            # Advanced forensics
            ;;
            
        *)
            log $LOG_WARN "$DAEMON_NAME" "Unknown action: $action"
            ;;
    esac
}

# Process playbook rules
process_playbooks() {
    local trigger_type=$1
    local ip=$2
    local value=$3
    
    # Read playbooks
    [[ -f "$PLAYBOOKS_FILE" ]] || return 0
    while IFS='|' read -r trigger condition action params; do
        # Skip comments and empty lines
        [[ "$trigger" =~ ^#.*$ ]] && continue
        [[ -z "$trigger" ]] && continue
        
        # Check if trigger matches
        if [[ "$trigger" == "$trigger_type" ]]; then
            # Check condition
            if check_condition "$condition" "$value"; then
                log $LOG_INFO "$DAEMON_NAME" "Playbook matched: $trigger|$condition|$action"
                execute_action "$action" "$ip" "$params"
            fi
        fi
    done < "$PLAYBOOKS_FILE"
}

# === Event Detectors ===

detect_port_scan() {
    local ip=$1
    local now=$(date +%s)
    local hour_ago=$((now - 3600))
    
    # Count unique ports accessed in last hour
    local unique_ports=$(sqlite3 "${DB_PATH}" \
        "SELECT COUNT(DISTINCT port) FROM connections WHERE ip='$ip' AND timestamp > $hour_ago;" 2>/dev/null || echo 0)
    
    if [[ $unique_ports -gt 5 ]]; then
        log $LOG_INFO "$DAEMON_NAME" "Port scan detected from $ip ($unique_ports ports)"
        process_playbooks "port_scan" "$ip" "$unique_ports"
    fi
}

detect_brute_force() {
    local ip=$1
    
    # Check honeypot logs for multiple failed attempts
    local ssh_attempts=$(grep -c "$ip" "${CYBERDECK_HOME}/logs/honeypots/ssh_${ip}"* 2>/dev/null || echo 0)
    
    if [[ $ssh_attempts -gt 3 ]]; then
        log $LOG_INFO "$DAEMON_NAME" "Brute force detected from $ip ($ssh_attempts attempts)"
        process_playbooks "ssh_honeypot" "$ip" "$ssh_attempts"
    fi
}

detect_high_frequency() {
    local ip=$1
    local now=$(date +%s)
    local hour_ago=$((now - 3600))
    
    # Count connections in last hour
    local conn_count=$(sqlite3 "${DB_PATH}" \
        "SELECT COUNT(*) FROM connections WHERE ip='$ip' AND timestamp > $hour_ago;" 2>/dev/null || echo 0)
    
    if [[ $conn_count -gt 50 ]]; then
        log $LOG_WARN "$DAEMON_NAME" "High frequency connections from $ip ($conn_count/hour)"
        process_playbooks "high_frequency" "$ip" "$conn_count"
    fi
}

detect_wordpress_attack() {
    local ip=$1
    
    # Check for WordPress honeypot hits
    if grep -q "$ip" "${CYBERDECK_HOME}/logs/honeypots/wordpress_${ip}"* 2>/dev/null; then
        log $LOG_INFO "$DAEMON_NAME" "WordPress attack from $ip"
        process_playbooks "wordpress_hit" "$ip" "1"
    fi
}

# === Main Loop ===

log $LOG_INFO "$DAEMON_NAME" "Monitoring for playbook triggers..."

while true; do
    db_heartbeat "$DAEMON_NAME"
    
    # Get recent active IPs (last 5 minutes)
    local now=$(date +%s)
    local five_min_ago=$((now - 300))
    
    local active_ips=$(sqlite3 "${DB_PATH}" \
        "SELECT DISTINCT ip FROM connections WHERE timestamp > $five_min_ago;" 2>/dev/null)
    
    for ip in $active_ips; do
        if validate_ip "$ip" && ! is_local_ip "$ip"; then
            # Run detectors
            detect_port_scan "$ip" &
            detect_brute_force "$ip" &
            detect_high_frequency "$ip" &
            detect_wordpress_attack "$ip" &
        fi
    done
    
    # Wait for background jobs
    wait
    
    # Sleep
    sleep 30
done
