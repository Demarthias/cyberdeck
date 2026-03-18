#!/bin/bash
# Containment Daemon - Quarantine and process management

set -euo pipefail

DAEMON_NAME="containment"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CYBERDECK_HOME="$(dirname "$SCRIPT_DIR")"
export CYBERDECK_HOME

source "${CYBERDECK_HOME}/lib/common.sh"
source "${CYBERDECK_HOME}/config/cyberdeck.conf"

if ! init_pidfile "$DAEMON_NAME"; then
    exit 1
fi

CONTAINMENT_PIPE=$(init_pipe "containment_queue")

cleanup() {
    daemon_cleanup "$DAEMON_NAME"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

log $LOG_INFO "$DAEMON_NAME" "Containment daemon started (PID: $$)"

QUARANTINE_DIR="${CYBERDECK_HOME}/quarantine"
mkdir -p "$QUARANTINE_DIR"

PROTECTED_PROCESSES=("bash" "zsh" "sh" "termux" "sshd" "systemd" "init" "supervisor")

is_protected_process() {
    local process_name="$1"
    for protected in "${PROTECTED_PROCESSES[@]}"; do
        [[ "$process_name" =~ $protected ]] && return 0
    done
    return 1
}

quarantine_ip() {
    local ip="$1" score="$2"
    log $LOG_INFO "$DAEMON_NAME" "Quarantining IP: $ip (score: $score)"
    
    local quarantine_file="${QUARANTINE_DIR}/${ip}_$(date +%s).log"
    cat > "$quarantine_file" <<EOF
=== QUARANTINE RECORD ===
IP: $ip
Threat Score: $score
Timestamp: $(date)

=== CONNECTION HISTORY ===
EOF
    
    exec_sql "SELECT timestamp, port, protocol FROM connections WHERE ip='$(sanitize_sql "$ip")' ORDER BY timestamp DESC LIMIT 100;" >> "$quarantine_file"
    log $LOG_INFO "$DAEMON_NAME" "Quarantine record: $quarantine_file"
}

while true; do
    update_heartbeat "$DAEMON_NAME"
    
    if read_pipe_safe "$CONTAINMENT_PIPE" 2 ip score action; then
        validate_ip "$ip" || continue
        is_local_ip "$ip" && continue
        
        [[ "$action" == "BLOCK" ]] && quarantine_ip "$ip" "$score"
    fi
    
    sleep "${CONTAINMENT_INTERVAL:-2}"
done
