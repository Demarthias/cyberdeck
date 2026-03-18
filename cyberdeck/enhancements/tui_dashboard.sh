#!/bin/bash
# TUI Dashboard - TIER 2
# Interactive terminal interface using dialog/whiptail

CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"

# Source shared library
source "${CYBERDECK_HOME}/lib/common.sh"
source "${CYBERDECK_HOME}/cockpit/cockpit.sh" 2>/dev/null || true

# Check if a daemon is running by PID file
is_running() {
    local daemon=$1
    local pid_file="${CYBERDECK_HOME}/pids/${daemon}.pid"
    [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

# Detect available TUI tool
TUI_TOOL=""
if command -v dialog >/dev/null 2>&1; then
    TUI_TOOL="dialog"
elif command -v whiptail >/dev/null 2>&1; then
    TUI_TOOL="whiptail"
else
    echo "ERROR: No TUI tool available. Install dialog or whiptail:"
    echo "  pkg install dialog"
    exit 1
fi

# === Helper Functions ===

show_message() {
    local title=$1
    local message=$2
    $TUI_TOOL --title "$title" --msgbox "$message" 20 70
}

show_status() {
    local status_text=$(cat <<EOF
=== CYBERDECK STATUS ===

$(cyberdeck_status 2>/dev/null || echo "Status unavailable")

Daemons Running:
$(ps aux | grep -E "(sensor|intel|firewall|containment|logging)" | grep -v grep | awk '{print $11}' | sort | uniq)

Recent Activity:
$(tail -5 "${CYBERDECK_HOME}/logs/sensor.log" 2>/dev/null || echo "No recent activity")
EOF
)
    
    $TUI_TOOL --title "Cyberdeck Status" --msgbox "$status_text" 25 80
}

show_threats() {
    local threats=$(sqlite3 "${DB_PATH}" \
        "SELECT ip, total_score, connection_count, CASE WHEN blocked=1 THEN '[BLOCKED]' ELSE '' END 
         FROM threats ORDER BY total_score DESC LIMIT 20;" 2>/dev/null | \
        awk -F'|' '{printf "%-15s  Score: %-3d  Conn: %-4d  %s\n", $1, $2, $3, $4}')
    
    if [[ -z "$threats" ]]; then
        threats="No threats detected"
    fi
    
    $TUI_TOOL --title "Top Threats" --msgbox "$threats" 25 80
}

show_alerts() {
    local alerts=$(sqlite3 "${DB_PATH}" \
        "SELECT datetime(timestamp,'unixepoch'), level, ip, message 
         FROM alerts ORDER BY timestamp DESC LIMIT 15;" 2>/dev/null | \
        awk -F'|' '{printf "%s [%s] %s: %s\n", $1, $2, $3, $4}')
    
    if [[ -z "$alerts" ]]; then
        alerts="No recent alerts"
    fi
    
    $TUI_TOOL --title "Recent Alerts" --msgbox "$alerts" 25 90
}

show_logs() {
    local daemon=$(
        $TUI_TOOL --title "Select Daemon" --menu "Choose daemon logs to view:" 15 50 5 \
            "sensor" "Network monitoring" \
            "intel" "Threat intelligence" \
            "firewall" "Blocking actions" \
            "containment" "Quarantine events" \
            "logging" "System logs" \
            3>&1 1>&2 2>&3
    )
    
    if [[ -n "$daemon" ]]; then
        local log_content=$(tail -50 "${CYBERDECK_HOME}/logs/${daemon}.log" 2>/dev/null || echo "Log file not found")
        $TUI_TOOL --title "$daemon Logs" --msgbox "$log_content" 25 100
    fi
}

block_ip_interactive() {
    local ip=$(
        $TUI_TOOL --title "Block IP" --inputbox "Enter IP address to block:" 10 50 \
            3>&1 1>&2 2>&3
    )
    
    if [[ -n "$ip" ]]; then
        if validate_ip "$ip"; then
            # Block via cyberdeck command
            cyberdeck block "$ip" >/dev/null 2>&1
            show_message "Success" "IP $ip has been blocked"
        else
            show_message "Error" "Invalid IP address: $ip"
        fi
    fi
}

unblock_ip_interactive() {
    # Show blocked IPs
    local blocked_ips=$(sqlite3 "${DB_PATH}" \
        "SELECT ip FROM threats WHERE blocked=1;" 2>/dev/null)
    
    if [[ -z "$blocked_ips" ]]; then
        show_message "Info" "No blocked IPs found"
        return
    fi
    
    local ip=$(
        $TUI_TOOL --title "Unblock IP" --inputbox "Enter IP address to unblock:\n\nCurrently blocked:\n$blocked_ips" 15 60 \
            3>&1 1>&2 2>&3
    )
    
    if [[ -n "$ip" ]]; then
        cyberdeck unblock "$ip" >/dev/null 2>&1
        show_message "Success" "IP $ip has been unblocked"
    fi
}

show_statistics() {
    local now=$(date +%s)
    local hour_ago=$((now - 3600))
    local day_ago=$((now - 86400))
    
    local stats=$(cat <<EOF
=== CYBERDECK STATISTICS ===

Total Threats Tracked:
  $(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM threats;" 2>/dev/null || echo 0)

Blocked IPs:
  $(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM threats WHERE blocked=1;" 2>/dev/null || echo 0)

Connections (Last Hour):
  $(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM connections WHERE timestamp > $hour_ago;" 2>/dev/null || echo 0)

Connections (Last 24h):
  $(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM connections WHERE timestamp > $day_ago;" 2>/dev/null || echo 0)

Alerts (Last Hour):
  $(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM alerts WHERE timestamp > $hour_ago;" 2>/dev/null || echo 0)

Most Active Ports:
$(sqlite3 "${DB_PATH}" "SELECT port, COUNT(*) as cnt FROM connections GROUP BY port ORDER BY cnt DESC LIMIT 5;" 2>/dev/null | awk -F'|' '{printf "  Port %s: %s connections\n", $1, $2}')

Top Threat Countries:
$(sqlite3 "${CYBERDECK_HOME}/cache/reputation_cache.db" "SELECT country, COUNT(*) as cnt FROM reputation WHERE country != '' GROUP BY country ORDER BY cnt DESC LIMIT 5;" 2>/dev/null | awk -F'|' '{printf "  %s: %s\n", $1, $2}')
EOF
)
    
    $TUI_TOOL --title "Statistics" --msgbox "$stats" 25 70
}

daemon_management() {
    local choice=$(
        $TUI_TOOL --title "Daemon Management" --menu "Choose action:" 15 60 5 \
            "start" "Start all daemons" \
            "stop" "Stop all daemons" \
            "restart" "Restart all daemons" \
            "status" "Check daemon status" \
            "health" "Run health check" \
            3>&1 1>&2 2>&3
    )
    
    case $choice in
        start)
            cyberdeck start
            show_message "Success" "Daemons started"
            ;;
        stop)
            cyberdeck stop
            show_message "Success" "Daemons stopped"
            ;;
        restart)
            cyberdeck restart
            show_message "Success" "Daemons restarted"
            ;;
        status)
            local daemon_status=$(
                for daemon in sensor intel firewall containment logging; do
                    if is_running "$daemon"; then
                        echo "$daemon: RUNNING"
                    else
                        echo "$daemon: STOPPED"
                    fi
                done
            )
            $TUI_TOOL --title "Daemon Status" --msgbox "$daemon_status" 15 50
            ;;
        health)
            local health_output=$(bash "${CYBERDECK_HOME}/healthcheck.sh" 2>&1)
            $TUI_TOOL --title "Health Check" --msgbox "$health_output" 25 90
            ;;
    esac
}

# === Main Menu ===

main_menu() {
    while true; do
        local choice=$(
            $TUI_TOOL --title "VENOM Cyberdeck - TUI Dashboard" \
                --menu "Select option:" 20 70 11 \
                "1" "View System Status" \
                "2" "View Top Threats" \
                "3" "View Recent Alerts" \
                "4" "View Daemon Logs" \
                "5" "View Statistics" \
                "6" "Block IP Address" \
                "7" "Unblock IP Address" \
                "8" "Daemon Management" \
                "9" "Refresh Display" \
                "0" "Exit" \
                3>&1 1>&2 2>&3
        )
        
        case $choice in
            1) show_status ;;
            2) show_threats ;;
            3) show_alerts ;;
            4) show_logs ;;
            5) show_statistics ;;
            6) block_ip_interactive ;;
            7) unblock_ip_interactive ;;
            8) daemon_management ;;
            9) clear ;;
            0|"") exit 0 ;;
        esac
    done
}

# === Startup ===

# Check if cyberdeck is installed
if [[ ! -d "$CYBERDECK_HOME" ]]; then
    echo "ERROR: Cyberdeck not found at $CYBERDECK_HOME"
    exit 1
fi

# Run main menu
main_menu
