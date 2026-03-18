#!/bin/bash
# Intelligence Daemon - Threat scoring and decision engine
# Receives sensor data, calculates threat scores, decides on actions

set -euo pipefail

DAEMON_NAME="intelligence"
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
INTEL_PIPE=$(init_pipe "intel_queue")
FIREWALL_PIPE=$(init_pipe "firewall_queue")
CONTAINMENT_PIPE=$(init_pipe "containment_queue")
COCKPIT_PIPE=$(init_pipe "cockpit_queue")

# Cleanup on exit
cleanup() {
    daemon_cleanup "$DAEMON_NAME"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

log $LOG_INFO "$DAEMON_NAME" "Intelligence daemon started (PID: $$)"

if [[ ${#SUSPICIOUS_PORTS[@]} -eq 0 ]]; then
    SUSPICIOUS_PORTS=(23 21 135 445 1433 3306 5432 6379 27017)
fi

if [[ ${#HIGH_RISK_PORTS[@]} -eq 0 ]]; then
    HIGH_RISK_PORTS=(22 3389 5900 4444 1337)
fi

# Calculate threat score for an IP
calculate_threat_score() {
    local ip="$1"
    local port="$2"
    local conn_count="$3"
    local score=0

    # Base score for any external connection
    ((score += ${SCORE_NEW_IP:-1}))

    # Port-based scoring
    for suspicious_port in "${SUSPICIOUS_PORTS[@]}"; do
        if [[ "$port" == "$suspicious_port" ]]; then
            ((score += ${SCORE_SUSPICIOUS_PORT:-2}))
            log $LOG_DEBUG "$DAEMON_NAME" "Suspicious port $port detected for $ip"
            break
        fi
    done
    
    for high_risk_port in "${HIGH_RISK_PORTS[@]}"; do
        if [[ "$port" == "$high_risk_port" ]]; then
            ((score += ${SCORE_HIGH_RISK_PORT:-3}))
            log $LOG_WARN "$DAEMON_NAME" "High-risk port $port detected for $ip"
            break
        fi
    done
    
    # Connection frequency scoring
    if ! [[ "$conn_count" =~ ^[0-9]+$ ]]; then
        conn_count=0
    fi
    if [[ $conn_count -gt ${CONN_FREQ_WARN:-10} ]]; then
        local freq_score
        freq_score=$(echo "$conn_count * ${SCORE_FREQ_MULTIPLIER:-0.5}" | bc 2>/dev/null) || freq_score=0
        freq_score=${freq_score:-0}
        score=$(echo "$score + $freq_score" | bc 2>/dev/null | cut -d. -f1) || true
        score=${score:-0}
        log $LOG_WARN "$DAEMON_NAME" "High connection frequency for $ip: $conn_count connections"
    fi
    
    # Check if IP was previously blocked
    local was_blocked=$(exec_sql "SELECT blocked FROM threats WHERE ip='$(sanitize_sql "$ip")';" | head -1)
    if [[ "$was_blocked" == "1" ]]; then
        ((score += ${SCORE_PREVIOUSLY_BLOCKED:-5}))
        log $LOG_WARN "$DAEMON_NAME" "Previously blocked IP reconnected: $ip"
    fi
    
    # Get historical score from database
    local historical_score=$(get_threat_score "$ip")
    if [[ -n "$historical_score" ]] && [[ "$historical_score" != "" ]]; then
        score=$((score + historical_score))
    fi
    
    echo "$score"
}

# Determine action based on threat score
determine_action() {
    local score=$1
    
    if [[ $score -ge ${THREAT_THRESHOLD_BLOCK:-8} ]]; then
        echo "BLOCK"
    elif [[ $score -ge ${THREAT_THRESHOLD_NOTIFY:-5} ]]; then
        echo "NOTIFY"
    else
        echo "LOG"
    fi
}

# Main processing loop
while true; do
    update_heartbeat "$DAEMON_NAME"
    
    # Read from intel queue with timeout
    if read_pipe_safe "$INTEL_PIPE" 2 ip port conn_count; then
        # Validate input
        if ! validate_ip "$ip"; then
            log $LOG_ERROR "$DAEMON_NAME" "Invalid IP received: $ip"
            continue
        fi
        
        log $LOG_DEBUG "$DAEMON_NAME" "Processing: $ip:$port (connections: $conn_count)"
        
        # Calculate threat score
        threat_score=$(calculate_threat_score "$ip" "$port" "$conn_count")
        
        # Update database
        [[ "$threat_score" =~ ^[0-9]+$ ]] || threat_score=0
        update_threat_score "$ip" "$threat_score"
        
        # Update last seen ports
        local safe_port
        safe_port=$(sanitize_sql "$port")
        exec_sql "UPDATE threats SET last_ports='$safe_port', connection_count=$conn_count WHERE ip='$(sanitize_sql "$ip")';"
        
        # Determine action
        action=$(determine_action "$threat_score")
        
        log $LOG_INFO "$DAEMON_NAME" "IP: $ip | Port: $port | Score: $threat_score | Action: $action"
        
        # Execute action
        case $action in
            BLOCK)
                # Send to firewall and containment
                send_to_pipe "$FIREWALL_PIPE" "$ip $threat_score BLOCK"
                send_to_pipe "$CONTAINMENT_PIPE" "$ip $threat_score BLOCK"

                # Send alert to cockpit
                send_to_pipe "$COCKPIT_PIPE" "RED $ip $threat_score BLOCKED"

                # Log alert
                local alert_msg="IP blocked due to threat score $threat_score"
                exec_sql "INSERT INTO alerts (timestamp, alert_type, ip, score, message)
                         VALUES ($(date +%s), 'BLOCK', '$(sanitize_sql "$ip")', $threat_score,
                                 '$(sanitize_sql "$alert_msg")');"
                
                # Update stats
                exec_sql "UPDATE stats SET value=value+1 WHERE key='total_threats_blocked';"
                
                log $LOG_CRITICAL "$DAEMON_NAME" "🚨 BLOCKING IP: $ip (score: $threat_score)"
                ;;
                
            NOTIFY)
                # Send warning to cockpit
                send_to_pipe "$COCKPIT_PIPE" "YELLOW $ip $threat_score SUSPICIOUS"

                # Log alert
                local alert_msg="Suspicious IP detected with score $threat_score"
                exec_sql "INSERT INTO alerts (timestamp, alert_type, ip, score, message)
                         VALUES ($(date +%s), 'WARNING', '$(sanitize_sql "$ip")', $threat_score,
                                 '$(sanitize_sql "$alert_msg")');"
                
                log $LOG_WARN "$DAEMON_NAME" "⚠️  SUSPICIOUS IP: $ip (score: $threat_score)"
                ;;
                
            LOG)
                # Just log it
                log $LOG_DEBUG "$DAEMON_NAME" "Monitoring IP: $ip (score: $threat_score)"
                ;;
        esac
        
        # Log action to database
        exec_sql "INSERT INTO actions (timestamp, action_type, ip, daemon, details) 
                 VALUES ($(date +%s), '$action', '$(sanitize_sql "$ip")', '$DAEMON_NAME', 
                         'Score: $threat_score, Port: $port');"
    fi
    
    sleep "${INTEL_INTERVAL:-2}"
done
