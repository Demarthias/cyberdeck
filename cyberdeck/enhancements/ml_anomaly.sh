#!/bin/bash
# ML Anomaly Detection - TIER 3
# Statistical anomaly detection using baseline behavior analysis

DAEMON_NAME="ml_anomaly"
CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"

# Source shared library
source "${CYBERDECK_HOME}/lib/common.sh"

# Initialize
write_pid "$DAEMON_NAME"
trap "daemon_cleanup \"$DAEMON_NAME\"" EXIT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 130" INT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 143" TERM

log $LOG_INFO "$DAEMON_NAME" "ML anomaly detection daemon starting..."

# === Configuration ===

ML_CACHE_DIR="${CYBERDECK_HOME}/cache/ml"
mkdir -p "$ML_CACHE_DIR"

BASELINE_FILE="${ML_CACHE_DIR}/baseline.db"
ANOMALY_THRESHOLD=2.5  # Standard deviations from mean

# Training period (hours of data before detecting anomalies)
TRAINING_PERIOD_HOURS=24

# === Baseline Database ===

sqlite3 "$BASELINE_FILE" <<SQL
CREATE TABLE IF NOT EXISTS port_baselines (
    port INTEGER PRIMARY KEY,
    mean_connections REAL,
    stddev_connections REAL,
    mean_score REAL,
    stddev_score REAL,
    last_updated INTEGER
);

CREATE TABLE IF NOT EXISTS ip_behavior (
    ip TEXT PRIMARY KEY,
    typical_ports TEXT,
    typical_connection_freq REAL,
    typical_session_duration REAL,
    first_seen INTEGER,
    profile_confidence REAL
);

CREATE TABLE IF NOT EXISTS time_baselines (
    hour INTEGER PRIMARY KEY,
    mean_connections REAL,
    stddev_connections REAL
);
SQL

# === Statistical Functions ===

calculate_mean() {
    local values=("$@")
    local sum=0
    local count=0
    
    for val in "${values[@]}"; do
        sum=$(echo "$sum + $val" | bc -l 2>/dev/null || echo 0)
        ((count++))
    done
    
    if [[ $count -gt 0 ]]; then
        echo "scale=2; $sum / $count" | bc -l
    else
        echo 0
    fi
}

calculate_stddev() {
    local mean=$1
    shift
    local values=("$@")
    
    local sum_sq_diff=0
    local count=0
    
    for val in "${values[@]}"; do
        local diff=$(echo "$val - $mean" | bc -l 2>/dev/null || echo 0)
        local sq=$(echo "$diff * $diff" | bc -l 2>/dev/null || echo 0)
        sum_sq_diff=$(echo "$sum_sq_diff + $sq" | bc -l 2>/dev/null || echo 0)
        ((count++))
    done
    
    if [[ $count -gt 1 ]]; then
        local variance=$(echo "scale=2; $sum_sq_diff / ($count - 1)" | bc -l)
        echo "sqrt($variance)" | bc -l
    else
        echo 0
    fi
}

# === Baseline Training ===

train_port_baseline() {
    local port=$1
    
    # Get historical connection counts for this port (last week)
    local week_ago=$(($(date +%s) - 604800))
    
    local conn_counts=$(sqlite3 "${DB_PATH}" \
        "SELECT COUNT(*) as cnt FROM connections WHERE port=$port AND timestamp > $week_ago GROUP BY DATE(timestamp, 'unixepoch');" \
        2>/dev/null | tr '\n' ' ')
    
    if [[ -z "$conn_counts" ]]; then
        return
    fi
    
    IFS=" " read -r -a counts_array <<< "$conn_counts"
    local mean=$(calculate_mean "${counts_array[@]}")
    local stddev=$(calculate_stddev "$mean" "${counts_array[@]}")
    
    # Store baseline
    sqlite3 "$BASELINE_FILE" <<SQL
INSERT OR REPLACE INTO port_baselines (port, mean_connections, stddev_connections, last_updated)
VALUES ($port, $mean, $stddev, $(date +%s));
SQL
    
    log $LOG_DEBUG "$DAEMON_NAME" "Port $port baseline: mean=$mean, stddev=$stddev"
}

train_time_baseline() {
    local hour=$1
    
    # Get connection counts for this hour over last week
    local week_ago=$(($(date +%s) - 604800))
    
    local conn_counts=$(sqlite3 "${DB_PATH}" \
        "SELECT COUNT(*) as cnt FROM connections 
         WHERE timestamp > $week_ago 
         AND CAST(strftime('%H', datetime(timestamp, 'unixepoch')) AS INTEGER) = $hour
         GROUP BY DATE(timestamp, 'unixepoch');" \
        2>/dev/null | tr '\n' ' ')
    
    if [[ -z "$conn_counts" ]]; then
        return
    fi
    
    IFS=" " read -r -a counts_array <<< "$conn_counts"
    local mean=$(calculate_mean "${counts_array[@]}")
    local stddev=$(calculate_stddev "$mean" "${counts_array[@]}")
    
    sqlite3 "$BASELINE_FILE" <<SQL
INSERT OR REPLACE INTO time_baselines (hour, mean_connections, stddev_connections)
VALUES ($hour, $mean, $stddev);
SQL
    
    log $LOG_DEBUG "$DAEMON_NAME" "Hour $hour baseline: mean=$mean, stddev=$stddev"
}

train_ip_behavior() {
    local ip=$1
    
    # Build behavior profile for this IP
    local typical_ports=$(sqlite3 "${DB_PATH}" \
        "SELECT GROUP_CONCAT(DISTINCT port) FROM connections WHERE ip='$ip' LIMIT 10;" 2>/dev/null)
    
    local first_seen=$(sqlite3 "${DB_PATH}" \
        "SELECT MIN(timestamp) FROM connections WHERE ip='$ip';" 2>/dev/null)
    
    local conn_freq=$(sqlite3 "${DB_PATH}" \
        "SELECT COUNT(*) * 1.0 / (MAX(timestamp) - MIN(timestamp) + 1) FROM connections WHERE ip='$ip';" 2>/dev/null)
    
    # Calculate confidence based on data points
    local data_points=$(sqlite3 "${DB_PATH}" \
        "SELECT COUNT(*) FROM connections WHERE ip='$ip';" 2>/dev/null)
    
    local confidence=0
    if [[ $data_points -gt 100 ]]; then
        confidence=1.0
    elif [[ $data_points -gt 50 ]]; then
        confidence=0.75
    elif [[ $data_points -gt 20 ]]; then
        confidence=0.5
    elif [[ $data_points -gt 5 ]]; then
        confidence=0.25
    fi
    
    local safe_ip; safe_ip=$(sanitize_sql "$ip")
    local safe_ports; safe_ports=$(sanitize_sql "$typical_ports")
    first_seen=${first_seen:-$(date +%s)}
    sqlite3 "$BASELINE_FILE" <<SQL
INSERT OR REPLACE INTO ip_behavior (ip, typical_ports, typical_connection_freq, first_seen, profile_confidence)
VALUES ('$safe_ip', '$safe_ports', $conn_freq, $first_seen, $confidence);
SQL
}

# === Anomaly Detection ===

detect_port_anomaly() {
    local port=$1
    local current_count=$2
    
    # Get baseline
    local baseline=$(sqlite3 "$BASELINE_FILE" \
        "SELECT mean_connections, stddev_connections FROM port_baselines WHERE port=$port;" 2>/dev/null)
    
    if [[ -z "$baseline" ]]; then
        return 0  # No baseline yet
    fi
    
    local mean=$(echo "$baseline" | cut -d'|' -f1)
    local stddev=$(echo "$baseline" | cut -d'|' -f2)
    
    # Calculate z-score
    local z_score=$(echo "scale=2; ($current_count - $mean) / $stddev" | bc -l 2>/dev/null || echo 0)
    local z_abs=$(echo "$z_score" | tr -d '-')
    
    # Check if anomalous
    if (( $(echo "$z_abs > $ANOMALY_THRESHOLD" | bc -l) )); then
        log $LOG_WARN "$DAEMON_NAME" "Port $port anomaly detected: z-score=$z_score (count=$current_count, mean=$mean)"
        return 1
    fi
    
    return 0
}

detect_ip_behavior_anomaly() {
    local ip=$1
    
    # Get behavior profile
    local profile=$(sqlite3 "$BASELINE_FILE" \
        "SELECT typical_ports, typical_connection_freq, profile_confidence FROM ip_behavior WHERE ip='$ip';" 2>/dev/null)
    
    if [[ -z "$profile" ]]; then
        return 0  # No profile yet
    fi
    
    local typical_ports=$(echo "$profile" | cut -d'|' -f1)
    local typical_freq=$(echo "$profile" | cut -d'|' -f2)
    local confidence=$(echo "$profile" | cut -d'|' -f3)
    
    # Only check if we have confident profile
    if (( $(echo "$confidence < 0.5" | bc -l) )); then
        return 0
    fi
    
    # Get current behavior (last hour)
    local now=$(date +%s)
    local hour_ago=$((now - 3600))
    
    local current_ports=$(sqlite3 "${DB_PATH}" \
        "SELECT GROUP_CONCAT(DISTINCT port) FROM connections WHERE ip='$ip' AND timestamp > $hour_ago;" 2>/dev/null)
    
    # Check for port deviation
    for port in $(echo "$current_ports" | tr ',' ' '); do
        if ! echo "$typical_ports" | grep -q "$port"; then
            log $LOG_WARN "$DAEMON_NAME" "IP $ip behavior anomaly: new port $port (typical: $typical_ports)"
            db_record_alert "$ip" "YELLOW" "ML: Unusual port access detected"
            db_record_threat "$ip" 2
            return 1
        fi
    done
    
    return 0
}

detect_time_anomaly() {
    local current_hour; current_hour=$((10#$(date +%H)))
    
    # Count connections in last hour
    local now=$(date +%s)
    local hour_ago=$((now - 3600))
    
    local current_count=$(sqlite3 "${DB_PATH}" \
        "SELECT COUNT(*) FROM connections WHERE timestamp > $hour_ago;" 2>/dev/null || echo 0)
    
    # Get baseline for this hour
    local baseline=$(sqlite3 "$BASELINE_FILE" \
        "SELECT mean_connections, stddev_connections FROM time_baselines WHERE hour=$current_hour;" 2>/dev/null)
    
    if [[ -z "$baseline" ]]; then
        return 0
    fi
    
    local mean=$(echo "$baseline" | cut -d'|' -f1)
    local stddev=$(echo "$baseline" | cut -d'|' -f2)
    
    # Calculate z-score
    local z_score=$(echo "scale=2; ($current_count - $mean) / $stddev" | bc -l 2>/dev/null || echo 0)
    local z_abs=$(echo "$z_score" | tr -d '-')
    
    if (( $(echo "$z_abs > $ANOMALY_THRESHOLD" | bc -l) )); then
        log $LOG_WARN "$DAEMON_NAME" "Time anomaly at hour $current_hour: z-score=$z_score (count=$current_count, mean=$mean)"
        # Don't return 1, just log - time anomalies might be normal
    fi
    
    return 0
}

# === Main Loop ===

log $LOG_INFO "$DAEMON_NAME" "Training initial baselines..."

# Train baselines for common ports
for port in 22 80 443 21 23 3306 5432 8080; do
    train_port_baseline "$port"
done

# Train baselines for all hours
for hour in {0..23}; do
    train_time_baseline "$hour"
done

log $LOG_INFO "$DAEMON_NAME" "Baseline training complete. Starting anomaly detection..."

LAST_TRAINING=$(date +%s)

while true; do
    db_heartbeat "$DAEMON_NAME"
    
    # Retrain baselines every 24 hours
    local now=$(date +%s)
    if [[ $((now - LAST_TRAINING)) -gt 86400 ]]; then
        log $LOG_INFO "$DAEMON_NAME" "Retraining baselines..."
        for port in 22 80 443 21 23 3306 5432 8080; do
            train_port_baseline "$port" &
        done
        for hour in {0..23}; do
            train_time_baseline "$hour" &
        done
        wait
        LAST_TRAINING=$now
    fi
    
    # Detect anomalies for recent activity
    detect_time_anomaly
    
    # Check active IPs
    local active_ips=$(sqlite3 "${DB_PATH}" \
        "SELECT DISTINCT ip FROM connections WHERE timestamp > $((now - 300));" 2>/dev/null)
    
    for ip in $active_ips; do
        if validate_ip "$ip" && ! is_local_ip "$ip"; then
            train_ip_behavior "$ip"
            detect_ip_behavior_anomaly "$ip"
        fi
    done
    
    # Sleep
    sleep 120
done
