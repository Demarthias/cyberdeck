#!/bin/bash
# Distributed Network Coordination - TIER 3
# Share threat intelligence and coordinate blocks across multiple cyberdeck instances

DAEMON_NAME="distributed"
CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"

# Source shared library
source "${CYBERDECK_HOME}/lib/common.sh"

# Initialize
write_pid "$DAEMON_NAME"
trap "daemon_cleanup \"$DAEMON_NAME\"" EXIT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 130" INT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 143" TERM

log $LOG_INFO "$DAEMON_NAME" "Distributed network daemon starting..."

# === Configuration ===

# Network mode: master, slave, or peer
NETWORK_MODE="${CYBERDECK_NETWORK_MODE:-peer}"

# Master node address (for slave mode)
MASTER_ADDRESS="${CYBERDECK_MASTER:-}"

# Peer addresses (for peer mode)
PEER_ADDRESSES="${CYBERDECK_PEERS:-}"  # Comma-separated

# Sync port
SYNC_PORT="${CYBERDECK_SYNC_PORT:-9999}"

# Shared threat database
SHARED_THREATS_DIR="${CYBERDECK_HOME}/cache/shared_threats"
mkdir -p "$SHARED_THREATS_DIR"

# Node ID (unique identifier for this instance)
NODE_ID=$(hostname)-$(date +%s)

# === Network Functions ===

# Simple HTTP-like protocol for threat sharing
send_threat_update() {
    local target_host=$1
    local ip=$2
    local score=$3
    local source=$4
    
    # Create JSON payload
    local payload=$(cat <<EOF
{
  "node_id": "$NODE_ID",
  "ip": "$ip",
  "score": $score,
  "timestamp": $(date +%s),
  "source": "$source"
}
EOF
)
    
    # Send via netcat (simple UDP broadcast)
    if command -v nc >/dev/null 2>&1; then
        echo "$payload" | nc -u -w1 "$target_host" "$SYNC_PORT" 2>/dev/null || true
    fi
    
    log $LOG_DEBUG "$DAEMON_NAME" "Sent threat update to $target_host: $ip (score $score)"
}

# Validate peer message has expected format (basic sanity check)
validate_peer_message() {
    local msg="$1"
    local peer_ip
    # Try jq first, fall back to grep
    if command -v jq >/dev/null 2>&1; then
        peer_ip=$(echo "$msg" | jq -r '.ip // empty' 2>/dev/null)
    else
        peer_ip=$(echo "$msg" | grep -oE '"ip"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -oE '[0-9a-fA-F:\.]+' | head -1)
    fi
    [[ -n "$peer_ip" ]] || return 1
    validate_ip "$peer_ip" || return 1
    return 0
}

# Receive threat updates from peers
receive_threat_updates() {
    local port=$1
    
    # Listen for incoming threat data
    if command -v nc >/dev/null 2>&1; then
        # Non-blocking receive
        local data=$(timeout 1 nc -l -u -p "$port" 2>/dev/null)
        
        if [[ -n "$data" ]]; then
            if validate_peer_message "$data"; then
                # Parse JSON (simple grep-based parsing)
                local remote_node=$(echo "$data" | grep -o '"node_id":"[^"]*"' | cut -d'"' -f4)
                local remote_ip=$(echo "$data" | grep -o '"ip":"[^"]*"' | cut -d'"' -f4)
                local remote_score=$(echo "$data" | grep -o '"score":[0-9]*' | cut -d: -f2)
                local remote_source=$(echo "$data" | grep -o '"source":"[^"]*"' | cut -d'"' -f4)

                log $LOG_INFO "$DAEMON_NAME" "Received threat from $remote_node: $remote_ip (score $remote_score)"

                # Add to our threat database with reduced score (trust factor)
                local trust_factor=0.5
                local adjusted_score=$(echo "scale=0; $remote_score * $trust_factor / 1" | bc)

                db_record_threat "$remote_ip" "$adjusted_score"
                db_record_alert "$remote_ip" "YELLOW" "Distributed: Threat shared from $remote_node ($remote_source)"

                # Store in shared threats file
                echo "$(date +%s)|$remote_node|$remote_ip|$remote_score|$remote_source" >> \
                    "${SHARED_THREATS_DIR}/received_threats.log"
            else
                log $LOG_WARN "$DAEMON_NAME" "Rejected invalid peer message"
            fi
        fi
    fi
}

# === Peer Discovery ===

discover_peers() {
    local broadcast_msg="CYBERDECK_DISCOVER:$NODE_ID:$SYNC_PORT"
    
    # Broadcast discovery on local network
    if command -v nc >/dev/null 2>&1; then
        echo "$broadcast_msg" | nc -u -b 255.255.255.255 "$SYNC_PORT" 2>/dev/null || true
    fi
    
    log $LOG_INFO "$DAEMON_NAME" "Peer discovery broadcast sent"
}

# === Threat Synchronization ===

sync_threats_to_peers() {
    # Get high-threat IPs to share (score >= 7)
    local high_threats=$(sqlite3 "${DB_PATH}" \
        "SELECT ip, total_score FROM threats WHERE total_score >= 7 AND last_seen > $(($(date +%s) - 3600));" \
        2>/dev/null)
    
    if [[ -z "$high_threats" ]]; then
        return 0
    fi
    
    # Parse peer addresses
    IFS=',' read -ra PEERS <<< "$PEER_ADDRESSES"
    
    while IFS='|' read -r ip score; do
        if [[ -n "$ip" ]] && validate_ip "$ip"; then
            # Send to all peers
            for peer in "${PEERS[@]}"; do
                if [[ -n "$peer" ]]; then
                    send_threat_update "$peer" "$ip" "$score" "local_detection"
                fi
            done
            
            # If in master mode, broadcast to all known slaves
            if [[ "$NETWORK_MODE" == "master" ]]; then
                # Would maintain list of connected slaves
                log $LOG_DEBUG "$DAEMON_NAME" "Master: Broadcasting threat $ip to slaves"
            fi
        fi
    done <<< "$high_threats"
}

# === Consensus Protocol (Simple Voting) ===

check_threat_consensus() {
    local ip=$1
    
    # Check if multiple nodes have reported this IP
    local reports=$(grep "$ip" "${SHARED_THREATS_DIR}/received_threats.log" 2>/dev/null | wc -l)
    
    if [[ $reports -ge 2 ]]; then
        log $LOG_WARN "$DAEMON_NAME" "Consensus: $ip reported by $reports nodes - increasing confidence"
        db_record_threat "$ip" 3  # Consensus boost
        db_record_alert "$ip" "YELLOW" "Distributed: Multi-node consensus detected"
    fi
}

# === Coordinated Blocking ===

coordinate_block() {
    local ip=$1
    
    # When we block an IP, notify peers
    IFS=',' read -ra PEERS <<< "$PEER_ADDRESSES"
    
    for peer in "${PEERS[@]}"; do
        if [[ -n "$peer" ]]; then
            send_threat_update "$peer" "$ip" 10 "coordinated_block"
        fi
    done
    
    log $LOG_INFO "$DAEMON_NAME" "Coordinated block initiated for $ip"
}

# === Main Loop ===

log $LOG_INFO "$DAEMON_NAME" "Network mode: $NETWORK_MODE"

if [[ "$NETWORK_MODE" == "slave" ]] && [[ -z "$MASTER_ADDRESS" ]]; then
    log $LOG_ERROR "$DAEMON_NAME" "Slave mode requires CYBERDECK_MASTER to be set"
    exit 1
fi

if [[ "$NETWORK_MODE" == "peer" ]] && [[ -z "$PEER_ADDRESSES" ]]; then
    log $LOG_WARN "$DAEMON_NAME" "Peer mode with no peers configured (set CYBERDECK_PEERS)"
fi

# Initial peer discovery
if [[ "$NETWORK_MODE" == "peer" ]]; then
    discover_peers
fi

LAST_SYNC=$(date +%s)
LAST_DISCOVERY=$(date +%s)

while true; do
    db_heartbeat "$DAEMON_NAME"
    
    local now=$(date +%s)
    
    # Receive threat updates
    receive_threat_updates "$SYNC_PORT"
    
    # Sync threats every 60 seconds
    if [[ $((now - LAST_SYNC)) -gt 60 ]]; then
        sync_threats_to_peers
        LAST_SYNC=$now
    fi
    
    # Peer discovery every 10 minutes
    if [[ "$NETWORK_MODE" == "peer" ]] && [[ $((now - LAST_DISCOVERY)) -gt 600 ]]; then
        discover_peers
        LAST_DISCOVERY=$now
    fi
    
    # Check for consensus on recent threats
    local recent_threats=$(sqlite3 "${DB_PATH}" \
        "SELECT DISTINCT ip FROM threats WHERE last_seen > $((now - 300));" 2>/dev/null)
    
    for ip in $recent_threats; do
        check_threat_consensus "$ip"
    done
    
    # Monitor for coordinated blocks
    local newly_blocked=$(sqlite3 "${DB_PATH}" \
        "SELECT ip FROM threats WHERE blocked=1 AND last_seen > $((now - 60));" 2>/dev/null)
    
    for ip in $newly_blocked; do
        coordinate_block "$ip"
    done
    
    # Brief sleep
    sleep 5
done
