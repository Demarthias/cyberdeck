#!/bin/bash
# Cyberdeck Cockpit HUD
# Add to your .zshrc or .bashrc

CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"

source "${CYBERDECK_HOME}/lib/common.sh"

# === Color Codes ===
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_BLUE="\033[34m"
COLOR_CYAN="\033[36m"
COLOR_BOLD="\033[1m"
COLOR_DIM="\033[2m"

# === Cockpit Functions ===

cyberdeck_status() {
    local db
    db=$(get_db_path)

    if [[ ! -f "$db" ]]; then
        echo -e "${COLOR_DIM}Cyberdeck not initialized${COLOR_RESET}"
        return
    fi
    
    # Get daemon status
    local running_daemons=0
    local total_daemons=0
    
    for daemon in sensor intel firewall containment logging; do
        ((total_daemons++))
        if [[ -f "${CYBERDECK_HOME}/pids/${daemon}.pid" ]]; then
            local pid=$(cat "${CYBERDECK_HOME}/pids/${daemon}.pid" 2>/dev/null)
            if kill -0 "$pid" 2>/dev/null; then
                ((running_daemons++))
            fi
        fi
    done
    
    # Get threat level
    local now=$(date +%s)
    local hour_ago=$((now - 3600))
    
    local red_alerts=$(sqlite3 "$db" \
        "SELECT COUNT(*) FROM alerts WHERE timestamp > $hour_ago AND alert_type='BLOCK';" 2>/dev/null || echo 0)
    local yellow_alerts=$(sqlite3 "$db" \
        "SELECT COUNT(*) FROM alerts WHERE timestamp > $hour_ago AND alert_type='WARNING';" 2>/dev/null || echo 0)
    local total_threats=$(sqlite3 "$db" \
        "SELECT COUNT(*) FROM threats;" 2>/dev/null || echo 0)
    local blocked_ips=$(sqlite3 "$db" \
        "SELECT COUNT(*) FROM threats WHERE blocked=1;" 2>/dev/null || echo 0)
    
    # Determine overall threat level
    local threat_color=$COLOR_GREEN
    local threat_symbol="●"
    local threat_status="SECURE"
    
    if [[ $red_alerts -gt 0 ]]; then
        threat_color=$COLOR_RED
        threat_symbol="⬤"
        threat_status="ALERT"
    elif [[ $yellow_alerts -gt 0 ]]; then
        threat_color=$COLOR_YELLOW
        threat_symbol="◆"
        threat_status="WATCH"
    fi
    
    # Build status line
    local status_line=""
    status_line+="${COLOR_BOLD}${COLOR_CYAN}[VENOM]${COLOR_RESET} "
    status_line+="${threat_color}${threat_symbol} ${threat_status}${COLOR_RESET} "
    status_line+="${COLOR_DIM}| Daemons: ${running_daemons}/${total_daemons} "
    status_line+="| Threats: ${total_threats} "
    status_line+="| Blocked: ${blocked_ips}${COLOR_RESET}"
    
    echo -e "$status_line"
}

cyberdeck_prompt() {
    # Get last command status
    local last_status=$?
    
    # Status indicator
    local status_color=$COLOR_GREEN
    local status_symbol="✓"
    
    if [[ $last_status -ne 0 ]]; then
        status_color=$COLOR_RED
        status_symbol="✗"
    fi
    
    # Get current threat level
    local db
    db=$(get_db_path)
    local threat_indicator=""

    if [[ -f "$db" ]]; then
        local now=$(date +%s)
        local minute_ago=$((now - 60))
        
        local recent_red=$(sqlite3 "$db" \
            "SELECT COUNT(*) FROM alerts WHERE timestamp > $minute_ago AND alert_type='BLOCK';" 2>/dev/null || echo 0)
        local recent_yellow=$(sqlite3 "$db" \
            "SELECT COUNT(*) FROM alerts WHERE timestamp > $minute_ago AND alert_type='WARNING';" 2>/dev/null || echo 0)
        
        if [[ $recent_red -gt 0 ]]; then
            threat_indicator="${COLOR_RED}[!]${COLOR_RESET} "
        elif [[ $recent_yellow -gt 0 ]]; then
            threat_indicator="${COLOR_YELLOW}[?]${COLOR_RESET} "
        fi
    fi
    
    # Build prompt
    echo -e "${threat_indicator}${status_color}${status_symbol}${COLOR_RESET}"
}

# === Cyberdeck Commands ===

cyberdeck() {
    local command=${1:-status}
    
    case $command in
        status|stat|s)
            echo ""
            echo "=== CYBERDECK STATUS ==="
            cyberdeck_status
            echo ""
            
            # Show recent alerts
            if [[ -f "$(get_db_path)" ]]; then
                echo "Recent Alerts (last 5):"
                sqlite3 "$(get_db_path)" \
                    "SELECT datetime(timestamp, 'unixepoch'), level, ip, message FROM alerts ORDER BY timestamp DESC LIMIT 5;" \
                    2>/dev/null | while IFS='|' read -r time level ip msg; do
                    case $level in
                        RED) echo -e "  ${COLOR_RED}●${COLOR_RESET} $time - $ip: $msg" ;;
                        YELLOW) echo -e "  ${COLOR_YELLOW}◆${COLOR_RESET} $time - $ip: $msg" ;;
                        *) echo -e "  ${COLOR_DIM}○${COLOR_RESET} $time - $ip: $msg" ;;
                    esac
                done
                echo ""
            fi
            ;;
            
        start)
            echo "Starting cyberdeck..."
            bash "${CYBERDECK_HOME}/supervisor.sh" &
            echo "Supervisor launched. Use 'cyberdeck status' to check."
            ;;
            
        stop)
            echo "Stopping cyberdeck..."
            for daemon in supervisor sensor intel firewall containment logging honeypot; do
                local pid_file="${CYBERDECK_HOME}/pids/${daemon}.pid"
                if [[ -f "$pid_file" ]]; then
                    local pid=$(cat "$pid_file")
                    if kill -0 "$pid" 2>/dev/null; then
                        echo "  Stopping $daemon (PID $pid)..."
                        kill -TERM "$pid" 2>/dev/null
                    fi
                fi
            done
            echo "Cyberdeck stopped."
            ;;
            
        restart)
            cyberdeck stop
            sleep 2
            cyberdeck start
            ;;
            
        logs|log|l)
            local daemon=${2:-sensor}
            local logfile="${CYBERDECK_HOME}/logs/${daemon}.log"
            
            if [[ -f "$logfile" ]]; then
                tail -n 20 "$logfile"
            else
                echo "Log file not found: $logfile"
            fi
            ;;
            
        threats|t)
            echo "=== TOP THREATS ==="
            sqlite3 "$(get_db_path)" \
                "SELECT ip, total_score, connection_count, CASE WHEN blocked=1 THEN 'BLOCKED' ELSE 'ACTIVE' END FROM threats ORDER BY total_score DESC LIMIT 10;" \
                2>/dev/null | while IFS='|' read -r ip score count status; do
                if [[ "$status" == "BLOCKED" ]]; then
                    echo -e "  ${COLOR_RED}⬤${COLOR_RESET} $ip (Score: $score, Connections: $count) ${COLOR_RED}$status${COLOR_RESET}"
                else
                    echo -e "  ${COLOR_YELLOW}◆${COLOR_RESET} $ip (Score: $score, Connections: $count) $status"
                fi
            done
            ;;
            
        block)
            local ip=$2
            if [[ -z "$ip" ]]; then
                echo "Usage: cyberdeck block <IP>"
                return 1
            fi

            validate_ip "$ip" || { echo "Invalid IP address: $ip" >&2; return 1; }
            ip=$(sanitize_sql "$ip")
            echo "Manually blocking $ip..."
            sqlite3 "$(get_db_path)" \
                "UPDATE threats SET blocked=1 WHERE ip='$ip';" 2>/dev/null
            
            # Add to blocked list
            echo "$ip" >> "${CYBERDECK_HOME}/config/blocked_ips.txt"
            echo "IP $ip blocked."
            ;;
            
        unblock)
            local ip=$2
            if [[ -z "$ip" ]]; then
                echo "Usage: cyberdeck unblock <IP>"
                return 1
            fi

            validate_ip "$ip" || { echo "Invalid IP address: $ip" >&2; return 1; }
            ip=$(sanitize_sql "$ip")
            echo "Unblocking $ip..."
            sqlite3 "$(get_db_path)" \
                "UPDATE threats SET blocked=0 WHERE ip='$ip';" 2>/dev/null
            
            # Remove from blocked list
            grep -vxF "$ip" "${CYBERDECK_HOME}/config/blocked_ips.txt" > "${CYBERDECK_HOME}/config/blocked_ips.txt.tmp" && mv "${CYBERDECK_HOME}/config/blocked_ips.txt.tmp" "${CYBERDECK_HOME}/config/blocked_ips.txt" 2>/dev/null || true
            echo "IP $ip unblocked."
            ;;
            
        help|h|--help)
            echo "Cyberdeck Command Center"
            echo ""
            echo "Usage: cyberdeck [command]"
            echo ""
            echo "Commands:"
            echo "  status, s       Show cyberdeck status"
            echo "  start           Start all daemons"
            echo "  stop            Stop all daemons"
            echo "  restart         Restart all daemons"
            echo "  logs [daemon]   View logs (default: sensor)"
            echo "  threats, t      Show top threats"
            echo "  block <IP>      Manually block an IP"
            echo "  unblock <IP>    Unblock an IP"
            echo "  help, h         Show this help"
            ;;
            
        *)
            echo "Unknown command: $command"
            echo "Use 'cyberdeck help' for available commands"
            ;;
    esac
}

# Auto-completion for cyberdeck command
if [[ -n "$ZSH_VERSION" ]]; then
    # Zsh completion
    compdef '_arguments "1:command:(status start stop restart logs threats block unblock help)"' cyberdeck
elif [[ -n "$BASH_VERSION" ]]; then
    # Bash completion
    _cyberdeck_completions() {
        local cur=${COMP_WORDS[COMP_CWORD]}
        COMPREPLY=( $(compgen -W "status start stop restart logs threats block unblock help" -- $cur) )
    }
    complete -F _cyberdeck_completions cyberdeck
fi

# === Initialize Cockpit ===

# Add status to prompt (optional - uncomment to enable)
# PS1="\$(cyberdeck_prompt) $PS1"

# Show startup banner
if [[ -t 0 ]] && [[ -f "$(get_db_path)" ]]; then
    echo ""
    cyberdeck_status
    echo ""
fi
