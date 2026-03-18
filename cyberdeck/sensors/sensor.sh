#!/bin/bash
# Sensor Daemon - Network connection monitoring
# Monitors TCP/UDP connections and sends data to intelligence layer

set -euo pipefail

DAEMON_NAME="sensor"
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

# Cleanup on exit
cleanup() {
    daemon_cleanup "$DAEMON_NAME"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

log $LOG_INFO "$DAEMON_NAME" "Sensor daemon started (PID: $$)"

# Connection tracking
declare -A connection_counts
declare -A last_seen

# Main monitoring loop
while true; do
    update_heartbeat "$DAEMON_NAME"
    
    # Get current established connections (using ss if available, netstat as fallback)
    if command -v ss &> /dev/null; then
        connections=$(ss -tnp 2>/dev/null || ss -tn 2>/dev/null)
    else
        connections=$(netstat -tn 2>/dev/null || echo "")
    fi
    
    # Process each connection
    while IFS= read -r line; do
        # Skip headers
        [[ "$line" =~ ^(State|Active|Proto) ]] && continue
        [[ -z "$line" ]] && continue
        
        # Parse connection info
        # Format varies, but typically: ESTAB 0 0 local_ip:port remote_ip:port
        if [[ "$line" =~ ESTAB|ESTABLISHED ]]; then
            # Extract remote IP and port
            remote=$(echo "$line" | awk 'NF>=5{print $5}' 2>/dev/null)
            
            if [[ -n "$remote" ]]; then
                # Split IP:port (IPv6-safe: split on last colon, strip brackets)
                ip="${remote%:*}"
                port="${remote##*:}"
                ip="${ip#[}"
                ip="${ip%]}"
                
                # Validate port is numeric
                [[ "$port" =~ ^[0-9]+$ ]] || continue

                # Validate IP
                if ! validate_ip "$ip"; then
                    continue
                fi
                
                # Skip local IPs
                if is_local_ip "$ip"; then
                    continue
                fi
                
                log $LOG_DEBUG "$DAEMON_NAME" "Detected connection from $ip:$port"
                
                # Track connection frequency
                current_time=$(date +%s)
                connection_key="${ip}_${current_time}"
                
                # Increment connection count for this IP
                if [[ -z "${connection_counts[$ip]:-}" ]]; then
                    connection_counts[$ip]=1
                    last_seen[$ip]=$current_time
                else
                    connection_counts[$ip]=$((${connection_counts[$ip]} + 1))
                fi
                
                # Log connection to database
                exec_sql "INSERT INTO connections (timestamp, ip, port, protocol, state) 
                         VALUES ($current_time, '$(sanitize_sql "$ip")', $port, 'TCP', 'ESTABLISHED');"
                
                # Send to intelligence layer with connection frequency
                conn_count=${connection_counts[$ip]}
                send_to_pipe "$INTEL_PIPE" "$ip $port $conn_count"
                
                log $LOG_DEBUG "$DAEMON_NAME" "Sent to intel: $ip (connections: $conn_count)"
            fi
        fi
    done <<< "$connections"
    
    # Cleanup old connection counts (older than 1 minute)
    current_time=$(date +%s)
    for ip in "${!last_seen[@]}"; do
        if [[ $((current_time - ${last_seen[$ip]})) -gt 60 ]]; then
            unset connection_counts[$ip]
            unset last_seen[$ip]
            log $LOG_DEBUG "$DAEMON_NAME" "Cleared connection count for $ip"
        fi
    done
    
    # Update stats
    total_conns=$(exec_sql "SELECT COUNT(*) FROM connections;")
    total_conns=${total_conns:-0}
    exec_sql "UPDATE stats SET value='$total_conns', updated=$(date +%s) WHERE key='total_connections_monitored';"
    
    sleep "${SENSOR_INTERVAL:-5}"
done
