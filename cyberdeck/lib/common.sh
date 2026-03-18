#!/bin/bash
# Common library for cyberdeck daemons
# Provides logging, validation, and utility functions

# Source configuration
CONFIG_FILE="${CYBERDECK_HOME:-$HOME/cyberdeck}/config/cyberdeck.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Color codes for logging
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging levels
readonly LOG_DEBUG=0
readonly LOG_INFO=1
readonly LOG_WARN=2
readonly LOG_ERROR=3
readonly LOG_CRITICAL=4

# Default log level
LOG_LEVEL=${LOG_LEVEL:-$LOG_INFO}

# Log function with levels
log() {
    local level=$1
    local daemon=$2
    shift 2
    local msg="$*"
    msg="${msg//$'\n'/ }"
    msg="${msg//$'\r'/ }"
    daemon="${daemon//[^a-zA-Z0-9_-]/}"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local level_name=""
    local color=""
    
    case $level in
        $LOG_DEBUG)
            level_name="DEBUG"
            color=$BLUE
            ;;
        $LOG_INFO)
            level_name="INFO"
            color=$GREEN
            ;;
        $LOG_WARN)
            level_name="WARN"
            color=$YELLOW
            ;;
        $LOG_ERROR)
            level_name="ERROR"
            color=$RED
            ;;
        $LOG_CRITICAL)
            level_name="CRITICAL"
            color=$RED
            ;;
    esac
    
    # Only log if level is high enough
    if [[ $level -ge $LOG_LEVEL ]]; then
        local log_file="${CYBERDECK_HOME:-$HOME/cyberdeck}/logs/${daemon}.log"
        echo "[$timestamp] [$level_name] [$daemon] $msg" >> "$log_file"
        chmod 600 "$log_file" 2>/dev/null || true
        
        # Also print to stderr for critical/error
        if [[ $level -ge $LOG_ERROR ]]; then
            echo -e "${color}[$level_name] [$daemon] $msg${NC}" >&2
        fi
    fi
}

# Validate IP address
validate_ip() {
    local ip=$1
    
    # IPv4 validation
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Check each octet is 0-255
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Check if IP is local/trusted
is_local_ip() {
    local ip=$1
    
    # Local patterns
    case $ip in
        127.*|localhost)
            return 0
            ;;
        10.*)
            return 0
            ;;
        192.168.*)
            return 0
            ;;
        172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
            return 0
            ;;
        169.254.*)  # Link-local
            return 0
            ;;
        ::1|fe80:*)  # IPv6 loopback and link-local
            return 0
            ;;
    esac
    
    # Check against configured trusted IPs
    if [[ -n "${TRUSTED_IPS:-}" ]]; then
        for trusted in "${TRUSTED_IPS[@]}"; do
            if [[ "$ip" == "$trusted" ]]; then
                return 0
            fi
        done
    fi
    
    return 1
}

# Initialize FIFO pipe safely
init_pipe() {
    local pipe=$1
    local pipe_path="${CYBERDECK_HOME:-$HOME/cyberdeck}/pipes/$pipe"
    
    # Remove if exists and is not a pipe
    if [[ -e "$pipe_path" ]] && [[ ! -p "$pipe_path" ]]; then
        rm -f "$pipe_path"
    fi
    
    # Create if doesn't exist
    if [[ ! -p "$pipe_path" ]]; then
        mkfifo "$pipe_path"
        chmod 600 "$pipe_path"  # Secure permissions
    fi
    
    echo "$pipe_path"
}

# Initialize PID file
init_pidfile() {
    local daemon_name=$1
    local pid_file="${CYBERDECK_HOME:-$HOME/cyberdeck}/pids/${daemon_name}.pid"
    local lock_file="${pid_file}.lock"

    mkdir -p "$(dirname "$pid_file")"

    # Atomic lock using flock
    exec 9>"$lock_file"
    if ! flock -n 9 2>/dev/null; then
        echo "Daemon $daemon_name already running" >&2
        exec 9>&-
        return 1
    fi

    # Check if process is actually running
    if [[ -f "$pid_file" ]]; then
        local old_pid
        old_pid=$(cat "$pid_file")
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "Daemon $daemon_name already running with PID $old_pid" >&2
            exec 9>&-
            return 1
        else
            rm -f "$pid_file"
        fi
    fi

    echo $$ > "$pid_file"
    exec 9>&-
    return 0
}

# Cleanup function for daemon shutdown
daemon_cleanup() {
    local daemon_name=$1
    local pid_file="${CYBERDECK_HOME:-$HOME/cyberdeck}/pids/${daemon_name}.pid"
    
    rm -f "$pid_file"
    log $LOG_INFO "$daemon_name" "Daemon stopped gracefully"
}

# Read from pipe with timeout
read_pipe_safe() {
    local pipe=$1
    local timeout=${2:-1}
    shift 2
    
    if read -t "$timeout" "$@" < "$pipe" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Send message to pipe (non-blocking)
send_to_pipe() {
    local pipe=$1
    shift
    local message="$*"

    if [[ -p "$pipe" ]]; then
        # Use timeout to prevent indefinite blocking
        if command -v timeout >/dev/null 2>&1; then
            timeout 1s bash -c "echo \"\$1\" > \"\$2\"" -- "$message" "$pipe" 2>/dev/null || true
        else
            echo "$message" > "$pipe" 2>/dev/null &
        fi
    fi
}

# Get SQLite database path
get_db_path() {
    echo "${CYBERDECK_HOME:-$HOME/cyberdeck}/config/threats.db"
}
DB_PATH=$(get_db_path)
export DB_PATH
readonly DB_PATH

# Execute SQL safely
exec_sql() {
    local query="$1"
    local db=$(get_db_path)
    
    sqlite3 "$db" "$query" 2>/dev/null
}

# Sanitize string for SQL (prevent injection)
sanitize_sql() {
    local input="$1"
    # Replace single quotes with two single quotes
    echo "${input//\'/\'\'}"
}

# Update heartbeat
update_heartbeat() {
    local daemon_name=$1
    local heartbeat_file="${CYBERDECK_HOME:-$HOME/cyberdeck}/pids/${daemon_name}.heartbeat"
    date +%s > "$heartbeat_file"
}

# Check if daemon is healthy (heartbeat within threshold)
check_daemon_health() {
    local daemon_name=$1
    local max_age=${2:-30}  # Default 30 seconds
    local heartbeat_file="${CYBERDECK_HOME:-$HOME/cyberdeck}/pids/${daemon_name}.heartbeat"
    
    if [[ ! -f "$heartbeat_file" ]]; then
        return 1
    fi
    
    local last_heartbeat=$(cat "$heartbeat_file")
    local now=$(date +%s)
    local age=$((now - last_heartbeat))
    
    if [[ $age -gt $max_age ]]; then
        return 1
    fi
    
    return 0
}

# Get threat score from database
get_threat_score() {
    local ip="$1"
    ip=$(sanitize_sql "$ip")
    
    exec_sql "SELECT total_score FROM threats WHERE ip='$ip';" | head -1
}

# Update threat score in database
update_threat_score() {
    local ip="$1"
    local score="$2"
    ip=$(sanitize_sql "$ip")
    
    local now=$(date +%s)
    
    exec_sql "INSERT INTO threats (ip, total_score, first_seen, last_seen, blocked) 
              VALUES ('$ip', $score, $now, $now, 0)
              ON CONFLICT(ip) DO UPDATE SET
                total_score=$score,
                last_seen=$now;"
}

# Mark IP as blocked in database
mark_blocked() {
    local ip="$1"
    ip=$(sanitize_sql "$ip")
    
    exec_sql "UPDATE threats SET blocked=1 WHERE ip='$ip';"
}

# Check if IP is already blocked
is_blocked() {
    local ip="$1"
    ip=$(sanitize_sql "$ip")
    
    local blocked=$(exec_sql "SELECT blocked FROM threats WHERE ip='$ip';" | head -1)
    [[ "$blocked" == "1" ]]
}

# Clean old threat records
cleanup_old_threats() {
    local retention_days=${THREAT_RETENTION_DAYS:-30}
    local cutoff=$(($(date +%s) - (retention_days * 86400)))
    
    exec_sql "DELETE FROM threats WHERE last_seen < $cutoff AND blocked=0;"
}

# Compatibility wrappers used by enhancement scripts
write_pid() {
    init_pidfile "$1"
}

db_record_threat() {
    local ip="$1"
    local score="$2"
    update_threat_score "$ip" "$score"
}

db_record_alert() {
    local ip="$1"
    local level="$2"
    local message="$3"
    ip=$(sanitize_sql "$ip")
    message=$(sanitize_sql "$message")
    exec_sql "INSERT INTO alerts (timestamp, alert_type, ip, score, message)
              VALUES ($(date +%s), '$level', '$ip', 0, '$message');"
}

db_heartbeat() {
    local daemon_name=$1
    update_heartbeat "$daemon_name"
}

db_get_threat_score() {
    get_threat_score "$1"
}

export -f log validate_ip is_local_ip init_pipe init_pidfile daemon_cleanup
export -f read_pipe_safe send_to_pipe get_db_path exec_sql sanitize_sql
export -f update_heartbeat check_daemon_health get_threat_score update_threat_score
export -f mark_blocked is_blocked cleanup_old_threats
export -f write_pid db_record_threat db_record_alert db_heartbeat db_get_threat_score
