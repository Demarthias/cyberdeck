#!/bin/bash
# Threat Intelligence Module - TIER 1
# Integrates with AbuseIPDB, AlienVault OTX, Tor Exit Nodes

DAEMON_NAME="threat_intel"
CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"
export CYBERDECK_HOME

# Source shared library
source "${CYBERDECK_HOME}/lib/common.sh"

# Initialize
write_pid "$DAEMON_NAME"
trap "daemon_cleanup \"$DAEMON_NAME\"" EXIT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 130" INT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 143" TERM

log $LOG_INFO "$DAEMON_NAME" "Threat Intelligence daemon starting..."

# === Configuration ===

# API Keys (set in environment or config)
ABUSEIPDB_API_KEY="${ABUSEIPDB_API_KEY:-}"
OTX_API_KEY="${OTX_API_KEY:-}"

# AbuseIPDB
ABUSEIPDB_URL="https://api.abuseipdb.com/api/v2/check"
ABUSEIPDB_CONFIDENCE_THRESHOLD=75

# Tor Exit Nodes
TOR_EXIT_LIST_URL="https://check.torproject.org/exit-addresses"
TOR_CACHE_FILE="${CYBERDECK_HOME}/cache/tor_exits.txt"
TOR_CACHE_HOURS=6

# AlienVault OTX
OTX_URL="https://otx.alienvault.com/api/v1/indicators/IPv4"

# Cache
CACHE_DIR="${CYBERDECK_HOME}/cache"
mkdir -p "$CACHE_DIR"
REPUTATION_CACHE="${CACHE_DIR}/reputation_cache.db"

# Rate limiting
LAST_API_CALL=0
API_RATE_LIMIT=2

# === Database Setup ===

sqlite3 "$REPUTATION_CACHE" <<SQL
CREATE TABLE IF NOT EXISTS reputation (
    ip TEXT PRIMARY KEY,
    source TEXT,
    confidence INTEGER,
    is_malicious BOOLEAN,
    categories TEXT,
    last_checked INTEGER,
    country TEXT,
    isp TEXT
);
CREATE INDEX IF NOT EXISTS idx_rep_checked ON reputation(last_checked);
SQL

# === Tor Exit Node Functions ===

update_tor_list() {
    local cache_age=0
    
    if [[ -f "$TOR_CACHE_FILE" ]]; then
        cache_age=$(( $(date +%s) - $(stat -c %Y "$TOR_CACHE_FILE" 2>/dev/null || stat -f %Y "$TOR_CACHE_FILE" 2>/dev/null || echo 0) ))
    fi
    
    if [[ $cache_age -gt $((TOR_CACHE_HOURS * 3600)) ]]; then
        log $LOG_INFO "$DAEMON_NAME" "Updating Tor exit node list..."
        
        if curl -s -m 30 "$TOR_EXIT_LIST_URL" 2>/dev/null | grep "ExitAddress" | awk '{print $2}' > "$TOR_CACHE_FILE.tmp"; then
            mv "$TOR_CACHE_FILE.tmp" "$TOR_CACHE_FILE"
            local count=$(wc -l < "$TOR_CACHE_FILE")
            log $LOG_INFO "$DAEMON_NAME" "Tor list updated: $count nodes"
        else
            log $LOG_ERROR "$DAEMON_NAME" "Failed to update Tor list"
            rm -f "$TOR_CACHE_FILE.tmp"
        fi
    fi
}

is_tor_exit() {
    local ip=$1
    [[ -f "$TOR_CACHE_FILE" ]] && grep -q "^${ip}$" "$TOR_CACHE_FILE" 2>/dev/null
}

# === AbuseIPDB Functions ===

check_abuseipdb() {
    local ip=$1
    
    [[ -z "$ABUSEIPDB_API_KEY" ]] && return 1
    
    # Rate limiting
    local now=$(date +%s)
    local wait=$((API_RATE_LIMIT - (now - LAST_API_CALL)))
    [[ $wait -gt 0 ]] && sleep $wait
    
    log $LOG_DEBUG "$DAEMON_NAME" "Checking AbuseIPDB for $ip"
    
    local response=$(curl -s -m 10 \
        -G "$ABUSEIPDB_URL" \
        -H "Key: $ABUSEIPDB_API_KEY" \
        -H "Accept: application/json" \
        --data-urlencode "ipAddress=$ip" \
        --data-urlencode "maxAgeInDays=90" 2>/dev/null)
    
    LAST_API_CALL=$(date +%s)
    
    [[ -z "$response" ]] && return 1
    
    # Parse JSON
    local confidence=$(echo "$response" | grep -o '"abuseConfidenceScore":[0-9]*' | cut -d: -f2)
    local country=$(echo "$response" | grep -o '"countryCode":"[^"]*"' | cut -d'"' -f4)
    local isp=$(echo "$response" | grep -o '"isp":"[^"]*"' | cut -d'"' -f4 | head -1)
    local is_whitelisted=$(echo "$response" | grep -o '"isWhitelisted":[a-z]*' | cut -d: -f2)
    
    [[ -z "$confidence" ]] && confidence=0
    
    local is_malicious=0
    [[ "$confidence" -ge "$ABUSEIPDB_CONFIDENCE_THRESHOLD" ]] && [[ "$is_whitelisted" != "true" ]] && is_malicious=1
    
    local safe_ip; safe_ip=$(sanitize_sql "$ip")
    local safe_country; safe_country=$(sanitize_sql "$country")
    local safe_isp; safe_isp=$(sanitize_sql "$(echo "$isp" | cut -c1-100)")
    sqlite3 "$REPUTATION_CACHE" <<SQL
INSERT OR REPLACE INTO reputation (ip, source, confidence, is_malicious, last_checked, country, isp)
VALUES ('$safe_ip', 'AbuseIPDB', $confidence, $is_malicious, $(date +%s), '$safe_country', '$safe_isp');
SQL
    
    if [[ $is_malicious -eq 1 ]]; then
        log $LOG_WARN "$DAEMON_NAME" "AbuseIPDB: $ip is malicious (confidence: $confidence%, country: $country)"
        return 0
    fi
    
    return 1
}

# === AlienVault OTX Functions ===

check_otx() {
    local ip=$1
    
    [[ -z "$OTX_API_KEY" ]] && return 1
    
    # Rate limiting
    local now=$(date +%s)
    local wait=$((API_RATE_LIMIT - (now - LAST_API_CALL)))
    [[ $wait -gt 0 ]] && sleep $wait
    
    log $LOG_DEBUG "$DAEMON_NAME" "Checking AlienVault OTX for $ip"
    
    local response=$(curl -s -m 10 \
        -H "X-OTX-API-KEY: $OTX_API_KEY" \
        "${OTX_URL}/${ip}/general" 2>/dev/null)
    
    LAST_API_CALL=$(date +%s)
    
    [[ -z "$response" ]] && return 1
    
    local pulse_count=$(echo "$response" | grep -o '"pulse_count":[0-9]*' | cut -d: -f2)
    
    if [[ -n "$pulse_count" ]] && [[ "$pulse_count" -gt 0 ]]; then
        log $LOG_WARN "$DAEMON_NAME" "OTX: $ip found in $pulse_count threat pulses"
        
        local safe_ip; safe_ip=$(sanitize_sql "$ip")
    sqlite3 "$REPUTATION_CACHE" <<SQL
INSERT OR REPLACE INTO reputation (ip, source, confidence, is_malicious, last_checked, categories)
VALUES ('$safe_ip', 'OTX', 80, 1, $(date +%s), 'threat_pulse');
SQL
        return 0
    fi
    
    return 1
}

# === Combined Reputation Check ===

check_ip_reputation() {
    local ip=$1
    local threat_boost=0
    local reputation_notes=""
    
    # Check cache (avoid repeated API calls within 24h)
    local safe_ip; safe_ip=$(sanitize_sql "$ip")
    local cache_age=$(sqlite3 "$REPUTATION_CACHE" \
        "SELECT ($(date +%s) - last_checked) FROM reputation WHERE ip='$safe_ip';" 2>/dev/null || echo 99999)

    if [[ $cache_age -lt 86400 ]]; then
        local cached_malicious=$(sqlite3 "$REPUTATION_CACHE" \
            "SELECT is_malicious FROM reputation WHERE ip='$safe_ip';" 2>/dev/null || echo 0)
        
        if [[ "$cached_malicious" -eq 1 ]]; then
            threat_boost=5
            reputation_notes="cached_malicious"
        fi
    else
        # Check Tor (free, no API)
        if is_tor_exit "$ip"; then
            threat_boost=3
            reputation_notes="tor_exit"
            log $LOG_INFO "$DAEMON_NAME" "IP $ip is a Tor exit node"
        fi
        
        # Check AbuseIPDB
        if check_abuseipdb "$ip"; then
            threat_boost=5
            reputation_notes="${reputation_notes:+$reputation_notes,}abuseipdb"
        fi
        
        # Check OTX
        if check_otx "$ip"; then
            threat_boost=5
            reputation_notes="${reputation_notes:+$reputation_notes,}otx"
        fi
    fi
    
    # Send threat boost to intelligence daemon
    if [[ $threat_boost -gt 0 ]]; then
        db_record_threat "$ip" "$threat_boost"
        db_record_alert "$ip" "YELLOW" "Threat intel: $reputation_notes (boost: +$threat_boost)"
        log $LOG_INFO "$DAEMON_NAME" "Threat boost for $ip: +$threat_boost ($reputation_notes)"
    fi
    
    return 0
}

# === Main Loop ===

log $LOG_INFO "$DAEMON_NAME" "Initializing threat intelligence feeds..."

update_tor_list
LAST_TOR_UPDATE=$(date +%s)

while true; do
    db_heartbeat "$DAEMON_NAME"
    
    # Update Tor list periodically
    local now=$(date +%s)
    if [[ $((now - LAST_TOR_UPDATE)) -gt $((TOR_CACHE_HOURS * 3600)) ]]; then
        update_tor_list
        LAST_TOR_UPDATE=$now
    fi
    
    # Check recent threats (last 5 minutes)
    local five_min_ago=$((now - 300))
    local recent_threats=$(sqlite3 "${DB_PATH}" \
        "SELECT DISTINCT ip FROM threats WHERE last_seen > $five_min_ago LIMIT 10;" 2>/dev/null)
    
    for ip in $recent_threats; do
        if validate_ip "$ip" && ! is_local_ip "$ip"; then
            check_ip_reputation "$ip"
        fi
    done
    
    # Sleep 60s (API calls are rate-limited)
    sleep 60
done
