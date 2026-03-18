#!/bin/bash
# Health Check Script

export CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"
source "${CYBERDECK_HOME}/lib/common.sh" 2>/dev/null || exit 1
source "${CYBERDECK_HOME}/config/cyberdeck.conf" 2>/dev/null || exit 1

echo "═══════════════════════════════════════"
echo "   CYBERDECK HEALTH CHECK"
echo "═══════════════════════════════════════"
echo ""

# Check daemons
echo "🔍 Daemon Status:"
echo ""

DAEMONS=("supervisor" "sensor" "intel" "firewall" "containment" "logging")
ALL_HEALTHY=true

for daemon in "${DAEMONS[@]}"; do
    pid_file="${CYBERDECK_HOME}/pids/${daemon}.pid"
    
    if [[ ! -f "$pid_file" ]]; then
        echo "  ❌ $daemon - NOT RUNNING"
        ALL_HEALTHY=false
        continue
    fi
    
    pid=$(cat "$pid_file")
    
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "  ❌ $daemon - DEAD (PID: $pid)"
        ALL_HEALTHY=false
        continue
    fi
    
    # Check heartbeat
    if check_daemon_health "$daemon" "${HEARTBEAT_TIMEOUT:-30}"; then
        echo "  ✅ $daemon - RUNNING (PID: $pid)"
    else
        echo "  ⚠️  $daemon - STALE HEARTBEAT (PID: $pid)"
        ALL_HEALTHY=false
    fi
done

echo ""

# System stats
echo "📊 System Statistics:"
echo ""

stats=$(exec_sql "SELECT key, value FROM stats;")
while IFS='|' read -r key value; do
    case $key in
        total_threats_blocked)
            echo "  🔒 Threats Blocked: $value"
            ;;
        total_connections_monitored)
            echo "  🔍 Connections Monitored: $value"
            ;;
        total_alerts_generated)
            echo "  ⚠️  Alerts Generated: $value"
            ;;
    esac
done <<< "$stats"

echo ""

# Recent threats
echo "🎯 Recent High-Threat IPs:"
echo ""

recent_threats=$(exec_sql "SELECT ip, total_score, blocked FROM threats WHERE total_score >= ${THREAT_THRESHOLD_NOTIFY:-5} ORDER BY last_seen DESC LIMIT 5;")

if [[ -z "$recent_threats" ]]; then
    echo "  ✅ No high-threat IPs detected"
else
    while IFS='|' read -r ip score blocked; do
        if [[ "$blocked" == "1" ]]; then
            echo "  🔴 $ip (score: $score) - BLOCKED"
        else
            echo "  🟡 $ip (score: $score) - MONITORING"
        fi
    done <<< "$recent_threats"
fi

echo ""

# Recent alerts
echo "🔔 Recent Alerts:"
echo ""

if [[ -f "${CYBERDECK_HOME}/logs/cockpit_alerts.txt" ]]; then
    tail -n 5 "${CYBERDECK_HOME}/logs/cockpit_alerts.txt" | while read -r alert; do
        echo "  $alert"
    done
else
    echo "  No alerts"
fi

echo ""
echo "═══════════════════════════════════════"

if [[ "$ALL_HEALTHY" == true ]]; then
    echo "  ✅ All systems operational"
else
    echo "  ⚠️  Some systems need attention"
fi

echo "═══════════════════════════════════════"
echo ""

exit 0
