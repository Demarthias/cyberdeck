#!/bin/bash
# Supervisor - Monitors and restarts daemons

set -euo pipefail

export CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"
source "${CYBERDECK_HOME}/lib/common.sh"
source "${CYBERDECK_HOME}/config/cyberdeck.conf"

SUPERVISOR_NAME="supervisor"

if ! init_pidfile "$SUPERVISOR_NAME"; then
    exit 1
fi

cleanup() {
    daemon_cleanup "$SUPERVISOR_NAME"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

log $LOG_INFO "$SUPERVISOR_NAME" "Supervisor started (PID: $$)"

DAEMONS=(
    "sensors/sensor.sh"
    "intelligence/intel.sh"
    "firewall/firewall.sh"
    "containment/containment.sh"
    "logging/logging.sh"
)

start_daemon() {
    local daemon_path="$1"
    local daemon_name=$(basename "$daemon_path" .sh)
    local pid_file="${CYBERDECK_HOME}/pids/${daemon_name}.pid"
    
    # Check if already running
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            # Check heartbeat
            if check_daemon_health "$daemon_name" "${HEARTBEAT_TIMEOUT:-30}"; then
                return 0
            else
                log $LOG_WARN "$SUPERVISOR_NAME" "Daemon $daemon_name heartbeat expired - restarting"
                kill "$pid" 2>/dev/null || true
                rm -f "$pid_file"
            fi
        else
            rm -f "$pid_file"
        fi
    fi
    
    # Start daemon
    log $LOG_INFO "$SUPERVISOR_NAME" "Starting daemon: $daemon_name"
    local logfile="${CYBERDECK_HOME}/logs/${daemon_name}.out"
    # Rotate log if over 10MB
    if [[ -f "$logfile" ]] && [[ $(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null || echo 0) -gt 10485760 ]]; then
        mv "$logfile" "${logfile}.old"
    fi
    nohup bash "${CYBERDECK_HOME}/${daemon_path}" >> "$logfile" 2>&1 &
    
    sleep 1
    
    # Verify it started
    if [[ -f "$pid_file" ]]; then
        local new_pid=$(cat "$pid_file")
        if kill -0 "$new_pid" 2>/dev/null; then
            log $LOG_INFO "$SUPERVISOR_NAME" "✅ Daemon $daemon_name started (PID: $new_pid)"
            return 0
        fi
    fi
    
    log $LOG_ERROR "$SUPERVISOR_NAME" "❌ Failed to start daemon: $daemon_name"
    return 1
}

while true; do
    update_heartbeat "$SUPERVISOR_NAME"
    
    for daemon in "${DAEMONS[@]}"; do
        start_daemon "$daemon"
    done
    
    # Cleanup old logs
    find "${CYBERDECK_HOME}/logs" -name "*.log" -mtime "+${LOG_RETENTION_DAYS:-7}" -delete 2>/dev/null || true
    
    # Cleanup old threat data
    cleanup_old_threats
    
    sleep "${SUPERVISOR_INTERVAL:-10}"
done
