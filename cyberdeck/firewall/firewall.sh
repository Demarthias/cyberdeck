#!/bin/bash
# Firewall Daemon - Connection blocking
# Blocks connections at app layer or via iptables (if root available)

set -euo pipefail

DAEMON_NAME="firewall"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CYBERDECK_HOME="$(dirname "$SCRIPT_DIR")"
export CYBERDECK_HOME

source "${CYBERDECK_HOME}/lib/common.sh"
source "${CYBERDECK_HOME}/config/cyberdeck.conf"

# Initialize daemon
if ! init_pidfile "$DAEMON_NAME"; then
    exit 1
fi

# Initialize pipes
FIREWALL_PIPE=$(init_pipe "firewall_queue")

# Cleanup on exit
cleanup() {
    daemon_cleanup "$DAEMON_NAME"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Check if we have root for iptables
HAS_ROOT=false
if [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null; then
    HAS_ROOT=true
    log $LOG_INFO "$DAEMON_NAME" "Root access detected - iptables available"
else
    log $LOG_INFO "$DAEMON_NAME" "No root access - using app-layer blocking"
fi

# Determine firewall mode
if [[ "${FIREWALL_MODE:-APP_LAYER}" == "IPTABLES" ]] && [[ "$HAS_ROOT" == false ]]; then
    log $LOG_WARN "$DAEMON_NAME" "IPTABLES mode requested but no root - falling back to APP_LAYER"
    FIREWALL_MODE="APP_LAYER"
fi

log $LOG_INFO "$DAEMON_NAME" "Firewall daemon started (PID: $$) - Mode: ${FIREWALL_MODE:-APP_LAYER}"

# Blocked IPs list file
BLOCKED_IPS_FILE="${CYBERDECK_HOME}/config/blocked_ips.txt"
touch "$BLOCKED_IPS_FILE"

# Block IP using iptables
block_ip_iptables() {
    local ip="$1"
    
    # Check if already blocked
    if sudo iptables -C INPUT -s "$ip" -j DROP 2>/dev/null; then
        log $LOG_DEBUG "$DAEMON_NAME" "IP $ip already blocked in iptables"
        return 0
    fi
    
    # Add iptables rule
    if sudo iptables -A INPUT -s "$ip" -j DROP 2>/dev/null; then
        log $LOG_INFO "$DAEMON_NAME" "✅ Blocked $ip via iptables"
        return 0
    else
        log $LOG_ERROR "$DAEMON_NAME" "❌ Failed to block $ip via iptables"
        return 1
    fi
}

# Block IP at application layer (add to blacklist)
block_ip_app_layer() {
    local ip="$1"
    
    # Check if already in blacklist
    if grep -qF "$ip" "$BLOCKED_IPS_FILE" 2>/dev/null; then
        log $LOG_DEBUG "$DAEMON_NAME" "IP $ip already in blacklist"
        return 0
    fi
    
    # Add to blacklist
    echo "$ip" >> "$BLOCKED_IPS_FILE"
    log $LOG_INFO "$DAEMON_NAME" "✅ Added $ip to application blacklist"
    
    # Kill existing connections from this IP
    kill_connections_from_ip "$ip"
    
    return 0
}

# Kill active connections from an IP
kill_connections_from_ip() {
    local ip="$1"
    local killed=0
    
    # Find PIDs with connections to this IP
    if command -v ss &> /dev/null; then
        while read -r pid; do
            if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
                # Don't kill critical processes
                local pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "")
                if [[ "$pname" =~ ^(bash|zsh|sh|termux|sshd|systemd|init|supervisor|python|ruby)$ ]]; then
                    log $LOG_WARN "$DAEMON_NAME" "Skipping critical process $pname ($pid)"
                    continue
                fi
                
                if kill -9 "$pid" 2>/dev/null; then
                    log $LOG_INFO "$DAEMON_NAME" "Killed process $pid connected to $ip"
                    ((killed++))
                fi
            fi
        done < <(ss -tnp | grep -F "$ip" | grep -o 'pid=[0-9]*' | cut -d= -f2 2>/dev/null)
    fi
    
    if [[ $killed -gt 0 ]]; then
        log $LOG_INFO "$DAEMON_NAME" "Killed $killed connection(s) from $ip"
    fi
}

# Unblock IP
unblock_ip() {
    local ip="$1"
    
    if [[ "${FIREWALL_MODE:-APP_LAYER}" == "IPTABLES" ]]; then
        if sudo iptables -D INPUT -s "$ip" -j DROP 2>/dev/null; then
            log $LOG_INFO "$DAEMON_NAME" "Unblocked $ip from iptables"
        fi
    fi
    
    # Remove from blacklist
    grep -vxF "$ip" "$BLOCKED_IPS_FILE" > "${BLOCKED_IPS_FILE}.tmp" && mv "${BLOCKED_IPS_FILE}.tmp" "$BLOCKED_IPS_FILE" || true
    log $LOG_INFO "$DAEMON_NAME" "Removed $ip from blacklist"
    
    # Update database
    exec_sql "UPDATE threats SET blocked=0 WHERE ip='$(sanitize_sql "$ip")';"
}

# Process a single block request
process_block_request() {
    local ip="$1"
    local score="$2"
    local action="$3"

    # Validate IP
    if ! validate_ip "$ip"; then
        log $LOG_ERROR "$DAEMON_NAME" "Invalid IP received: $ip"
        return
    fi

    # Skip local IPs (safety check)
    if is_local_ip "$ip"; then
        log $LOG_WARN "$DAEMON_NAME" "Attempted to block local IP $ip - SKIPPED"
        return
    fi

    # Check if already blocked
    if is_blocked "$ip"; then
        log $LOG_DEBUG "$DAEMON_NAME" "IP $ip already blocked"
        return
    fi

    [[ "$score" =~ ^[0-9]+$ ]] || score=0
    log $LOG_INFO "$DAEMON_NAME" "Processing block request: $ip (score: $score, action: $action)"

    # Execute block
    if [[ "$action" == "BLOCK" ]]; then
        local success=false

        if [[ "${FIREWALL_MODE:-APP_LAYER}" == "IPTABLES" ]]; then
            if block_ip_iptables "$ip"; then
                success=true
            fi
        else
            if block_ip_app_layer "$ip"; then
                success=true
            fi
        fi

        if [[ "$success" == true ]]; then
            # Mark as blocked in database
            mark_blocked "$ip"
            exec_sql "UPDATE threats SET block_time=$(date +%s) WHERE ip='$(sanitize_sql "$ip")';"

            # Log action
            exec_sql "INSERT INTO actions (timestamp, action_type, ip, daemon, details, success)
                     VALUES ($(date +%s), 'BLOCK', '$(sanitize_sql "$ip")', '$DAEMON_NAME',
                             'Score: $score, Mode: ${FIREWALL_MODE}', 1);"

            log $LOG_CRITICAL "$DAEMON_NAME" "🔒 IP BLOCKED: $ip (threat score: $score)"
        else
            log $LOG_ERROR "$DAEMON_NAME" "Failed to block $ip"

            exec_sql "INSERT INTO actions (timestamp, action_type, ip, daemon, details, success)
                     VALUES ($(date +%s), 'BLOCK', '$(sanitize_sql "$ip")', '$DAEMON_NAME',
                             'Score: $score, Mode: ${FIREWALL_MODE}', 0);"
        fi
    fi
}

# Main blocking loop
while true; do
    update_heartbeat "$DAEMON_NAME"

    # Read from firewall queue with timeout
    if read_pipe_safe "$FIREWALL_PIPE" 2 ip score action; then
        process_block_request "$ip" "$score" "$action"
    fi
    
    sleep "${FIREWALL_INTERVAL:-1}"
done
