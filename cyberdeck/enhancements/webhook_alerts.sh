#!/bin/bash
# Webhook Alerting Module - TIER 1
# Sends alerts to Discord, Slack, and custom webhooks

DAEMON_NAME="webhook_alerts"
CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"

# Source shared library
source "${CYBERDECK_HOME}/lib/common.sh"

# Initialize
write_pid "$DAEMON_NAME"
trap "daemon_cleanup \"$DAEMON_NAME\"" EXIT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 130" INT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 143" TERM

log $LOG_INFO "$DAEMON_NAME" "Webhook alerting daemon starting..."

# === Configuration ===

# Webhook URLs (set in environment or config)
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
CUSTOM_WEBHOOK_URL="${CUSTOM_WEBHOOK_URL:-}"

# Alert settings
WEBHOOK_ENABLED="${WEBHOOK_ENABLED:-true}"
WEBHOOK_MIN_SEVERITY="${WEBHOOK_MIN_SEVERITY:-YELLOW}"  # YELLOW or RED only
WEBHOOK_RATE_LIMIT=30  # Seconds between alerts for same IP

# Track last alert time per IP
declare -A LAST_WEBHOOK_ALERT

# === Discord Webhook Functions ===

send_discord_alert() {
    local level=$1
    local ip=$2
    local message=$3
    
    [[ -z "$DISCORD_WEBHOOK_URL" ]] && return 1
    
    # Color coding
    local color="16776960"  # Yellow
    [[ "$level" == "RED" ]] && color="16711680"  # Red
    [[ "$level" == "GREEN" ]] && color="65280"    # Green
    
    # Emoji
    local emoji="⚠️"
    [[ "$level" == "RED" ]] && emoji="🔴"
    [[ "$level" == "GREEN" ]] && emoji="✅"
    
    # Build JSON payload
    local json=$(cat <<EOF
{
  "embeds": [{
    "title": "${emoji} Cyberdeck Alert",
    "description": "$message",
    "color": $color,
    "fields": [
      {
        "name": "IP Address",
        "value": "$ip",
        "inline": true
      },
      {
        "name": "Severity",
        "value": "$level",
        "inline": true
      },
      {
        "name": "Timestamp",
        "value": "$(date '+%Y-%m-%d %H:%M:%S')",
        "inline": false
      }
    ],
    "footer": {
      "text": "VENOM Cyberdeck"
    }
  }]
}
EOF
)
    
    # Send webhook
    if curl -s -m 10 -X POST \
        -H "Content-Type: application/json" \
        -d "$json" \
        "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1; then
        log $LOG_INFO "$DAEMON_NAME" "Discord alert sent for $ip"
        return 0
    else
        log $LOG_ERROR "$DAEMON_NAME" "Failed to send Discord alert"
        return 1
    fi
}

# === Slack Webhook Functions ===

send_slack_alert() {
    local level=$1
    local ip=$2
    local message=$3
    
    [[ -z "$SLACK_WEBHOOK_URL" ]] && return 1
    
    # Color coding
    local color="warning"
    [[ "$level" == "RED" ]] && color="danger"
    [[ "$level" == "GREEN" ]] && color="good"
    
    # Build JSON payload
    local json=$(cat <<EOF
{
  "attachments": [
    {
      "color": "$color",
      "title": "🛡️ Cyberdeck Alert",
      "text": "$message",
      "fields": [
        {
          "title": "IP Address",
          "value": "$ip",
          "short": true
        },
        {
          "title": "Severity",
          "value": "$level",
          "short": true
        }
      ],
      "footer": "VENOM Cyberdeck",
      "ts": $(date +%s)
    }
  ]
}
EOF
)
    
    # Send webhook
    if curl -s -m 10 -X POST \
        -H "Content-Type: application/json" \
        -d "$json" \
        "$SLACK_WEBHOOK_URL" >/dev/null 2>&1; then
        log $LOG_INFO "$DAEMON_NAME" "Slack alert sent for $ip"
        return 0
    else
        log $LOG_ERROR "$DAEMON_NAME" "Failed to send Slack alert"
        return 1
    fi
}

# === Custom Webhook Functions ===

send_custom_webhook() {
    local level=$1
    local ip=$2
    local message=$3
    
    [[ -z "$CUSTOM_WEBHOOK_URL" ]] && return 1
    
    # Simple JSON payload
    local json=$(cat <<EOF
{
  "severity": "$level",
  "ip": "$ip",
  "message": "$message",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source": "cyberdeck"
}
EOF
)
    
    # Send webhook
    if curl -s -m 10 -X POST \
        -H "Content-Type: application/json" \
        -d "$json" \
        "$CUSTOM_WEBHOOK_URL" >/dev/null 2>&1; then
        log $LOG_INFO "$DAEMON_NAME" "Custom webhook sent for $ip"
        return 0
    else
        log $LOG_ERROR "$DAEMON_NAME" "Failed to send custom webhook"
        return 1
    fi
}

# === Alert Dispatcher ===

send_webhook_alert() {
    local level=$1
    local ip=$2
    local message=$3
    
    # Check if webhooks are enabled
    [[ "$WEBHOOK_ENABLED" != "true" ]] && return 0
    
    # Check severity threshold
    if [[ "$WEBHOOK_MIN_SEVERITY" == "RED" ]] && [[ "$level" != "RED" ]]; then
        return 0
    fi
    
    # Rate limiting per IP
    local now=$(date +%s)
    local last_alert=${LAST_WEBHOOK_ALERT[$ip]:-0}
    local time_since_alert=$((now - last_alert))
    
    if [[ $time_since_alert -lt $WEBHOOK_RATE_LIMIT ]]; then
        log $LOG_DEBUG "$DAEMON_NAME" "Rate limit: skipping alert for $ip (${time_since_alert}s since last)"
        return 0
    fi
    
    # Update last alert time
    LAST_WEBHOOK_ALERT[$ip]=$now
    
    # Send to all configured webhooks
    send_discord_alert "$level" "$ip" "$message" &
    send_slack_alert "$level" "$ip" "$message" &
    send_custom_webhook "$level" "$ip" "$message" &

    # Wait for webhook calls with timeout
    local deadline=$(($(date +%s) + 10))
    for job in $(jobs -p 2>/dev/null); do
        local remaining=$((deadline - $(date +%s)))
        [[ $remaining -le 0 ]] && break
        wait "$job" 2>/dev/null || true
    done
    # Kill any remaining background jobs
    jobs -p 2>/dev/null | xargs -r kill 2>/dev/null || true

    return 0
}

# === Main Loop ===

log $LOG_INFO "$DAEMON_NAME" "Monitoring for alerts to webhook..."

# Check configuration
if [[ -z "$DISCORD_WEBHOOK_URL" ]] && [[ -z "$SLACK_WEBHOOK_URL" ]] && [[ -z "$CUSTOM_WEBHOOK_URL" ]]; then
    log $LOG_WARN "$DAEMON_NAME" "No webhook URLs configured. Set DISCORD_WEBHOOK_URL, SLACK_WEBHOOK_URL, or CUSTOM_WEBHOOK_URL"
fi

while true; do
    db_heartbeat "$DAEMON_NAME"
    
    # Read alerts from database (recent alerts in last 10 seconds)
    local now=$(date +%s)
    local recent_alerts=$(sqlite3 "${DB_PATH}" \
        "SELECT ip, alert_type, message FROM alerts WHERE timestamp > $((now - 10)) ORDER BY timestamp DESC LIMIT 5;" 2>/dev/null)

    while IFS='|' read -r ip alert_type message; do
        if [[ -n "$ip" ]] && [[ -n "$alert_type" ]]; then
            send_webhook_alert "$alert_type" "$ip" "$message"
        fi
    done <<< "$recent_alerts"
    
    # Sleep
    sleep 5
done
