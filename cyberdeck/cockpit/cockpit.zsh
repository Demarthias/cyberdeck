# Cyberdeck Cockpit - ZSH Integration
# Source this in your .zshrc for HUD prompt

export CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"

# Cockpit functions
cyberdeck_status() {
    local alerts_file="${CYBERDECK_HOME}/logs/cockpit_alerts.txt"
    local status="GREEN"
    
    if [[ -f "$alerts_file" ]]; then
        if tail -n 1 "$alerts_file" 2>/dev/null | grep -q "RED"; then
            status="RED"
        elif tail -n 1 "$alerts_file" 2>/dev/null | grep -q "YELLOW"; then
            status="YELLOW"
        fi
    fi
    
    echo "$status"
}

cyberdeck_prompt() {
    local status=$(cyberdeck_status)
    local color="%F{green}"
    local symbol="✓"
    
    case $status in
        RED)
            color="%F{red}"
            symbol="⚠"
            ;;
        YELLOW)
            color="%F{yellow}"
            symbol="⚡"
            ;;
    esac
    
    echo "${color}[${symbol}]%f"
}

# Cyberdeck commands
alias cyberdeck-start='bash "$CYBERDECK_HOME/supervisor.sh" &'
alias cyberdeck-stop='bash "$CYBERDECK_HOME/stop.sh"'
alias cyberdeck-status='bash "$CYBERDECK_HOME/healthcheck.sh"'
alias cyberdeck-logs='tail -f "$CYBERDECK_HOME/logs/*.log"'
alias cyberdeck-alerts='tail -f "$CYBERDECK_HOME/logs/cockpit_alerts.txt"'
alias cyberdeck-threats='sqlite3 "$CYBERDECK_HOME/config/threats.db" "SELECT ip, total_score, blocked FROM threats WHERE total_score >= 5 ORDER BY total_score DESC LIMIT 10;"'

# Add to prompt (customize as desired)
# Example: PROMPT='$(cyberdeck_prompt) %n@%m %~ %# '

# Cockpit HUD (advanced - full screen)
cyberdeck_hud() {
    while true; do
        clear
        echo "════════════════════════════════════════════════════════════════"
        echo "                     CYBERDECK COCKPIT HUD                      "
        echo "════════════════════════════════════════════════════════════════"
        echo ""
        
        # Daemon status
        echo "🖥️  DAEMON STATUS:"
        for daemon in supervisor sensor intel firewall containment logging; do
            pid_file="${CYBERDECK_HOME}/pids/${daemon}.pid"
            if [[ -f "$pid_file" ]] && kill -0 $(cat "$pid_file") 2>/dev/null; then
                echo "  ✅ $daemon"
            else
                echo "  ❌ $daemon"
            fi
        done
        
        echo ""
        echo "📊 SYSTEM STATS:"
        sqlite3 "${CYBERDECK_HOME}/config/threats.db" "SELECT '  🔒 Blocked: ' || value FROM stats WHERE key='total_threats_blocked';" 2>/dev/null || echo "  🔒 Blocked: N/A"
        sqlite3 "${CYBERDECK_HOME}/config/threats.db" "SELECT '  🔍 Monitored: ' || value FROM stats WHERE key='total_connections_monitored';" 2>/dev/null || echo "  🔍 Monitored: N/A"
        
        echo ""
        echo "🎯 ACTIVE THREATS:"
        sqlite3 "${CYBERDECK_HOME}/config/threats.db" "SELECT '  ' || CASE WHEN blocked=1 THEN '🔴' ELSE '🟡' END || ' ' || ip || ' (score: ' || total_score || ')' FROM threats WHERE total_score >= 5 ORDER BY total_score DESC LIMIT 5;" 2>/dev/null || echo "  None"
        
        echo ""
        echo "🔔 RECENT ALERTS:"
        tail -n 5 "${CYBERDECK_HOME}/logs/cockpit_alerts.txt" 2>/dev/null | sed 's/^/  /' || echo "  No alerts"
        
        echo ""
        echo "════════════════════════════════════════════════════════════════"
        echo "  Press Ctrl+C to exit | Refreshes every 5 seconds"
        echo "════════════════════════════════════════════════════════════════"
        
        sleep 5
    done
}

# Notification on new threats (if cockpit enabled)
if [[ "${COCKPIT_ENABLED:-true}" == "true" ]]; then
    # Check for new alerts on prompt display (lightweight)
    precmd() {
        local last_alert=$(tail -n 1 "${CYBERDECK_HOME}/logs/cockpit_alerts.txt" 2>/dev/null)
        if [[ -n "$last_alert" ]] && [[ "$last_alert" != "${CYBERDECK_LAST_ALERT:-}" ]]; then
            export CYBERDECK_LAST_ALERT="$last_alert"
            if [[ "$last_alert" =~ RED ]]; then
                echo "\n🚨 CYBERDECK ALERT: $last_alert\n"
            fi
        fi
    }
fi
