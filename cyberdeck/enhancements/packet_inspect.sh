#!/bin/bash
# Packet Inspection Module - TIER 3
# Deep packet inspection and protocol fingerprinting

DAEMON_NAME="packet_inspect"
CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"

# Source shared library
source "${CYBERDECK_HOME}/lib/common.sh"

# Initialize
write_pid "$DAEMON_NAME"
trap "daemon_cleanup \"$DAEMON_NAME\"" EXIT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 130" INT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 143" TERM

log $LOG_INFO "$DAEMON_NAME" "Packet inspection daemon starting..."

# === Configuration ===

PCAP_DIR="${CYBERDECK_HOME}/pcaps"
mkdir -p "$PCAP_DIR"

# Check for tcpdump
HAS_TCPDUMP=false
if command -v tcpdump >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
    HAS_TCPDUMP=true
    log $LOG_INFO "$DAEMON_NAME" "tcpdump available (root access detected)"
elif command -v tcpdump >/dev/null 2>&1; then
    log $LOG_WARN "$DAEMON_NAME" "tcpdump available but requires root - packet capture disabled"
else
    log $LOG_WARN "$DAEMON_NAME" "tcpdump not available - packet inspection limited to connection analysis"
fi

# Signature database for exploit detection
SIGNATURES_FILE="${CYBERDECK_HOME}/cache/signatures.txt"

# Create default signatures if not exists
if [[ ! -f "$SIGNATURES_FILE" ]]; then
    cat > "$SIGNATURES_FILE" <<'EOF'
# Packet signatures for common attacks
# Format: PATTERN|THREAT_NAME|SCORE

\x90\x90\x90\x90|NOP_SLED|8
/etc/passwd|FILE_INCLUSION|7
/bin/sh|SHELL_INJECTION|8
SELECT.*FROM.*WHERE|SQL_INJECTION|7
<script>|XSS_ATTEMPT|6
cmd.exe|WINDOWS_EXPLOIT|7
nc -e|NETCAT_REVERSE_SHELL|9
wget.*\|.*sh|DOWNLOAD_EXECUTE|8
Union.*Select|SQL_UNION|7
../../../../|PATH_TRAVERSAL|6
eval\(|CODE_INJECTION|7
system\(|COMMAND_INJECTION|8
EOF
fi

# === Protocol Fingerprinting ===

identify_protocol() {
    local port=$1
    local payload=$2
    
    # Known protocol signatures
    case $port in
        80|8080|8000)
            if echo "$payload" | grep -qiE "^(GET|POST|PUT|DELETE|HEAD|OPTIONS)"; then
                echo "HTTP"
                return 0
            fi
            ;;
        443|8443)
            if echo "$payload" | head -c 3 | xxd -p | grep -q "^16030"; then
                echo "TLS/HTTPS"
                return 0
            fi
            ;;
        22|2222)
            if echo "$payload" | grep -q "^SSH-"; then
                echo "SSH"
                return 0
            fi
            ;;
        21)
            if echo "$payload" | grep -qiE "^220.*FTP"; then
                echo "FTP"
                return 0
            fi
            ;;
        25|587)
            if echo "$payload" | grep -qiE "^220.*SMTP"; then
                echo "SMTP"
                return 0
            fi
            ;;
        3306)
            echo "MySQL"
            return 0
            ;;
        5432)
            echo "PostgreSQL"
            return 0
            ;;
        3389)
            echo "RDP"
            return 0
            ;;
    esac
    
    # Generic detection by payload
    if echo "$payload" | grep -qE "^\x16\x03"; then
        echo "TLS"
    elif echo "$payload" | grep -qiE "^(GET|POST).*HTTP"; then
        echo "HTTP"
    else
        echo "UNKNOWN"
    fi
}

# === Payload Analysis ===

analyze_payload() {
    local ip=$1
    local port=$2
    local payload=$3
    
    local threats_found=0
    local threat_names=""
    
    # Check against signatures
    while IFS='|' read -r pattern threat_name score; do
        # Skip comments
        [[ "$pattern" =~ ^#.*$ ]] && continue
        [[ -z "$pattern" ]] && continue
        
        if echo "$payload" | grep -qE "$pattern" 2>/dev/null; then
            log $LOG_WARN "$DAEMON_NAME" "Threat signature detected from $ip: $threat_name"
            threat_names="${threat_names:+$threat_names,}$threat_name"
            db_record_threat "$ip" "$score"
            ((threats_found++))
        fi
    done < "$SIGNATURES_FILE"
    
    if [[ $threats_found -gt 0 ]]; then
        db_record_alert "$ip" "RED" "DPI: Malicious signatures detected ($threat_names)"
        log $LOG_WARN "$DAEMON_NAME" "IP $ip triggered $threats_found signature(s): $threat_names"
    fi
    
    return $threats_found
}

# === Tool Detection ===

detect_scanning_tools() {
    local ip=$1
    local payload=$2
    
    # Common scanning tool signatures
    if echo "$payload" | grep -qiE "(nmap|masscan|zmap|unicornscan)"; then
        log $LOG_WARN "$DAEMON_NAME" "Scanning tool detected from $ip: $(echo "$payload" | grep -oiE "(nmap|masscan|zmap|unicornscan)")"
        db_record_threat "$ip" 5
        db_record_alert "$ip" "YELLOW" "DPI: Network scanning tool detected"
        return 0
    fi
    
    # Metasploit signatures
    if echo "$payload" | grep -qiE "(metasploit|meterpreter|msf)"; then
        log $LOG_WARN "$DAEMON_NAME" "Metasploit detected from $ip"
        db_record_threat "$ip" 8
        db_record_alert "$ip" "RED" "DPI: Metasploit framework detected"
        return 0
    fi
    
    # Nikto/dirb web scanners
    if echo "$payload" | grep -qiE "(nikto|dirb|dirbuster)"; then
        log $LOG_WARN "$DAEMON_NAME" "Web scanner detected from $ip"
        db_record_threat "$ip" 4
        db_record_alert "$ip" "YELLOW" "DPI: Web vulnerability scanner detected"
        return 0
    fi
    
    return 1
}

# === Packet Capture (if root) ===

capture_suspicious_traffic() {
    local ip=$1
    local duration=${2:-30}
    
    if [[ "$HAS_TCPDUMP" != "true" ]]; then
        return 1
    fi
    
    local pcap_file="${PCAP_DIR}/${ip}_$(date +%s).pcap"
    
    log $LOG_INFO "$DAEMON_NAME" "Capturing packets from $ip for ${duration}s"
    
    # Capture in background
    timeout "$duration" tcpdump -i any -w "$pcap_file" host "$ip" >/dev/null 2>&1 &
    
    # Log capture
    db_record_alert "$ip" "YELLOW" "DPI: Packet capture initiated"
    
    return 0
}

# === Connection Analysis (Without Packet Capture) ===

analyze_connection_pattern() {
    local ip=$1
    
    # Get recent connections for pattern analysis
    local now=$(date +%s)
    local minute_ago=$((now - 60))
    
    # Connection timing analysis
    local timestamps=$(sqlite3 "${DB_PATH}" \
        "SELECT timestamp FROM connections WHERE ip='$ip' AND timestamp > $minute_ago ORDER BY timestamp;" \
        2>/dev/null | tr '\n' ' ')
    
    if [[ -z "$timestamps" ]]; then
        return 0
    fi
    
    local timestamps_array=($timestamps)
    local count=${#timestamps_array[@]}
    
    if [[ $count -lt 3 ]]; then
        return 0
    fi
    
    # Calculate inter-arrival times
    local intervals=()
    for ((i=1; i<count; i++)); do
        local interval=$((timestamps_array[i] - timestamps_array[i-1]))
        intervals+=($interval)
    done
    
    # Check for automated/scripted behavior (very regular intervals)
    local regular_intervals=0
    for interval in "${intervals[@]}"; do
        # If intervals are exactly 1 second apart = likely automated
        if [[ $interval -eq 1 ]]; then
            ((regular_intervals++))
        fi
    done
    
    if [[ $regular_intervals -gt $((count / 2)) ]]; then
        log $LOG_WARN "$DAEMON_NAME" "Automated/scripted behavior detected from $ip"
        db_record_alert "$ip" "YELLOW" "DPI: Automated connection pattern detected"
        db_record_threat "$ip" 3
    fi
    
    # Check for burst behavior (many connections in short time)
    if [[ $count -gt 20 ]]; then
        log $LOG_WARN "$DAEMON_NAME" "Connection burst detected from $ip ($count connections in 60s)"
        db_record_alert "$ip" "YELLOW" "DPI: Connection burst pattern"
        db_record_threat "$ip" 2
    fi
}

# === Main Loop ===

log $LOG_INFO "$DAEMON_NAME" "Packet inspection engine initialized"

if [[ "$HAS_TCPDUMP" == "true" ]]; then
    log $LOG_INFO "$DAEMON_NAME" "Packet capture enabled"
else
    log $LOG_INFO "$DAEMON_NAME" "Running in connection analysis mode (no packet capture)"
fi

while true; do
    db_heartbeat "$DAEMON_NAME"
    
    # Get recent high-threat IPs
    local now=$(date +%s)
    local recent=$(((now - 120)))
    
    local suspicious_ips=$(sqlite3 "${DB_PATH}" \
        "SELECT DISTINCT ip FROM threats WHERE total_score >= 5 AND last_seen > $recent;" 2>/dev/null)
    
    for ip in $suspicious_ips; do
        if validate_ip "$ip" && ! is_local_ip "$ip"; then
            # Analyze connection patterns
            analyze_connection_pattern "$ip"
            
            # Capture packets if very suspicious
            local score=$(db_get_threat_score "$ip")
            if [[ $score -ge 7 ]] && [[ "$HAS_TCPDUMP" == "true" ]]; then
                capture_suspicious_traffic "$ip" 30 &
            fi
        fi
    done
    
    # Analyze honeypot payloads if available
    find "${CYBERDECK_HOME}/logs/honeypots" -name "*.log" -mmin -5 2>/dev/null | while read -r logfile; do
        local ip=$(basename "$logfile" | cut -d'_' -f2)
        if [[ -n "$ip" ]]; then
            local payload=$(tail -100 "$logfile")
            analyze_payload "$ip" "0" "$payload"
            detect_scanning_tools "$ip" "$payload"
        fi
    done
    
    # Sleep
    sleep 30
done
