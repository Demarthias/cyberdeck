#!/bin/bash
# Logging Daemon - Central logging and alert aggregation

set -euo pipefail

DAEMON_NAME="logging"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CYBERDECK_HOME="$(dirname "$SCRIPT_DIR")"
export CYBERDECK_HOME

source "${CYBERDECK_HOME}/lib/common.sh"
source "${CYBERDECK_HOME}/config/cyberdeck.conf"

if ! init_pidfile "$DAEMON_NAME"; then
    exit 1
fi

COCKPIT_PIPE=$(init_pipe "cockpit_queue")

cleanup() {
    daemon_cleanup "$DAEMON_NAME"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

log $LOG_INFO "$DAEMON_NAME" "Logging daemon started (PID: $$)"

COCKPIT_ALERTS="${CYBERDECK_HOME}/logs/cockpit_alerts.txt"
touch "$COCKPIT_ALERTS"

while true; do
    update_heartbeat "$DAEMON_NAME"
    
    if read_pipe_safe "$COCKPIT_PIPE" 1 color ip score status; then
        local timestamp=$(date '+%H:%M:%S')
        local alert_msg="[$timestamp] [$color] $ip (score: $score) - $status"
        
        echo "$alert_msg" >> "$COCKPIT_ALERTS"
        (
            flock -x 200
            if [[ -f "$COCKPIT_ALERTS" ]] && [[ $(wc -l < "$COCKPIT_ALERTS") -gt 100 ]]; then
                local tmpfile
                tmpfile=$(mktemp) || return 1
                tail -n 50 "$COCKPIT_ALERTS" > "$tmpfile" && mv "$tmpfile" "$COCKPIT_ALERTS" || rm -f "$tmpfile"
            fi
        ) 200>"${COCKPIT_ALERTS}.lock"
        
        exec_sql "UPDATE stats SET value=value+1, updated=$(date +%s) WHERE key='total_alerts_generated';"
        
        log $LOG_INFO "$DAEMON_NAME" "Alert: $alert_msg"
    fi
    
    sleep 1
done
