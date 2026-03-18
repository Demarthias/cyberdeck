#!/bin/bash
# Enhanced Honeypots - TIER 2
# Realistic fake services: SSH (Cowrie-style), WordPress, MySQL, RDP signals

DAEMON_NAME="enhanced_honeypots"
CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"

# Source shared library
source "${CYBERDECK_HOME}/lib/common.sh"

# Initialize
write_pid "$DAEMON_NAME"
trap "daemon_cleanup \"$DAEMON_NAME\"" EXIT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 130" INT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 143" TERM

log $LOG_INFO "$DAEMON_NAME" "Enhanced honeypot daemon starting..."

# === Configuration ===

HONEYPOT_LOG_DIR="${CYBERDECK_HOME}/logs/honeypots"
mkdir -p "$HONEYPOT_LOG_DIR"

# Common credentials tried by attackers (for logging)
COMMON_USERNAMES=("root" "admin" "user" "test" "ubuntu" "oracle" "postgres" "mysql")
COMMON_PASSWORDS=("password" "123456" "admin" "root" "password123" "12345678")

# === Enhanced SSH Honeypot (Cowrie-style) ===

fake_ssh_advanced() {
    local client_ip=$1
    local session_id="$(date +%s)_$$"
    local log_file="${HONEYPOT_LOG_DIR}/ssh_${client_ip}_${session_id}.log"
    
    echo "[$(date)] SSH connection from $client_ip" >> "$log_file"
    
    # Realistic SSH banner
    echo "SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.1"
    sleep 0.5
    
    # Key exchange (simplified)
    echo "[$(date)] Key exchange initiated" >> "$log_file"
    
    # Wait for authentication
    local attempt=0
    while [[ $attempt -lt 3 ]]; do
        if read -t 30 auth_line; then
            echo "[$(date)] Auth attempt $((attempt+1)): $auth_line" >> "$log_file"
            
            # Extract username/password if visible
            if echo "$auth_line" | grep -qiE "user|password"; then
                local username=$(echo "$auth_line" | grep -oE 'user[^:]*:[^:]*' | cut -d: -f2 | tr -d ' ')
                local password=$(echo "$auth_line" | grep -oE 'pass[^:]*:[^:]*' | cut -d: -f2 | tr -d ' ')
                
                if [[ -n "$username" ]]; then
                    echo "[$(date)] Username: $username" >> "$log_file"
                    db_record_alert "$client_ip" "YELLOW" "SSH honeypot: username=$username"
                fi
            fi
            
            # Always reject
            echo "Permission denied, please try again."
            ((attempt++))
        else
            break
        fi
    done
    
    echo "Too many authentication failures"
    
    # High threat score for SSH honeypot hits
    db_record_threat "$client_ip" 4
    log $LOG_INFO "$DAEMON_NAME" "SSH honeypot hit from $client_ip ($attempt attempts)"
}

# === Fake WordPress Login ===

fake_wordpress() {
    local client_ip=$1
    local log_file="${HONEYPOT_LOG_DIR}/wordpress_${client_ip}_$(date +%s).log"
    
    echo "[$(date)] HTTP connection from $client_ip" >> "$log_file"
    
    # Read HTTP request
    local request_line=""
    local headers=""
    local body=""
    local content_length=0
    
    # Read request line
    read -t 5 request_line
    echo "$request_line" >> "$log_file"
    
    # Read headers
    while read -t 2 line; do
        headers+="$line"$'\n'
        [[ -z "$line" ]] && break
        
        # Extract Content-Length
        if [[ "$line" =~ Content-Length:[[:space:]]*([0-9]+) ]]; then
            content_length=${BASH_REMATCH[1]}
        fi
    done
    echo "$headers" >> "$log_file"
    
    # Read body if POST
    if [[ $content_length -gt 0 ]] && [[ $content_length -lt 10000 ]]; then
        body=$(head -c $content_length)
        echo "$body" >> "$log_file"
        
        # Extract credentials from POST data
        if echo "$body" | grep -q "log=.*&pwd="; then
            local username=$(echo "$body" | grep -o 'log=[^&]*' | cut -d= -f2 | head -1)
            local password=$(echo "$body" | grep -o 'pwd=[^&]*' | cut -d= -f2 | head -1)
            
            # URL decode
            username=$(echo "$username" | sed 's/%20/ /g' | sed 's/%40/@/g')
            password=$(echo "$password" | sed 's/%20/ /g')
            
            echo "[$(date)] WordPress login attempt: $username / $password" >> "$log_file"
            db_record_alert "$client_ip" "YELLOW" "WordPress honeypot: user=$username"
            
            # Very high threat score for WordPress attacks
            db_record_threat "$client_ip" 5
        fi
    fi
    
    # Check for common WordPress attacks in URL
    if echo "$request_line" | grep -qiE "(wp-admin|wp-login|xmlrpc|wp-json|wp-config)"; then
        log $LOG_WARN "$DAEMON_NAME" "WordPress attack pattern from $client_ip"
        db_record_threat "$client_ip" 3
    fi
    
    # Send realistic WordPress response
    cat <<'EOF'
HTTP/1.1 200 OK
Server: Apache/2.4.41 (Ubuntu)
Content-Type: text/html; charset=UTF-8
Connection: close

<!DOCTYPE html>
<html lang="en-US">
<head>
    <meta charset="UTF-8">
    <title>Log In &lsaquo; MyBlog &mdash; WordPress</title>
</head>
<body class="login login-action-login wp-core-ui">
    <div id="login">
        <h1><a href="https://wordpress.org/">Powered by WordPress</a></h1>
        <form name="loginform" id="loginform" action="/wp-login.php" method="post">
            <p>
                <label for="user_login">Username or Email Address</label>
                <input type="text" name="log" id="user_login" class="input" value="" size="20" autocapitalize="off" />
            </p>
            <p>
                <label for="user_pass">Password</label>
                <input type="password" name="pwd" id="user_pass" class="input" value="" size="20" />
            </p>
            <p class="submit">
                <input type="submit" name="wp-submit" id="wp-submit" class="button button-primary button-large" value="Log In" />
            </p>
        </form>
        <p id="nav">
            <a href="/wp-login.php?action=lostpassword">Lost your password?</a>
        </p>
    </div>
</body>
</html>
EOF
    
    log $LOG_INFO "$DAEMON_NAME" "WordPress honeypot hit from $client_ip"
}

# === Fake MySQL Service ===

fake_mysql() {
    local client_ip=$1
    local log_file="${HONEYPOT_LOG_DIR}/mysql_${client_ip}_$(date +%s).log"
    
    echo "[$(date)] MySQL connection from $client_ip" >> "$log_file"
    
    # MySQL handshake packet (simplified)
    # Protocol version (10) + Server version + Connection ID
    printf "\x0a5.7.33-0ubuntu0.18.04.1\x00"
    printf "\x01\x00\x00\x00"  # Connection ID
    
    # Random bytes (scramble)
    head -c 20 /dev/urandom
    
    # Capabilities
    printf "\x00\xff\xff\x21\x02\x00\x00\x00"
    
    # Wait for login attempt
    if read -t 10 -N 100 login_data; then
        echo "[$(date)] Login attempt received" >> "$log_file"
        echo "$login_data" | xxd >> "$log_file"
        
        # Always send error
        printf "\x47\x00\x00\x02\xff\x15\x04Access denied for user"
        
        db_record_threat "$client_ip" 4
        log $LOG_INFO "$DAEMON_NAME" "MySQL honeypot hit from $client_ip"
    fi
}

# === Fake RDP/Windows Service ===

fake_rdp() {
    local client_ip=$1
    local log_file="${HONEYPOT_LOG_DIR}/rdp_${client_ip}_$(date +%s).log"
    
    echo "[$(date)] RDP-style connection from $client_ip" >> "$log_file"
    
    # Simplified RDP-like response
    printf "\x03\x00\x00\x13\x0e\xd0\x00\x00\x124\x00\x02\x01\x08\x00\x02\x00\x00\x00"
    
    # Wait for data
    if read -t 10 -N 100 rdp_data; then
        echo "[$(date)] RDP data received" >> "$log_file"
        
        db_record_threat "$client_ip" 4
        log $LOG_INFO "$DAEMON_NAME" "RDP honeypot hit from $client_ip"
    fi
}

# === Generic Port Listener ===

start_honeypot_service() {
    local port=$1
    local handler=$2
    local service_name=$3
    
    log $LOG_INFO "$DAEMON_NAME" "Starting $service_name honeypot on port $port"
    
    # Use socat if available, fallback to nc
    if command -v socat >/dev/null 2>&1; then
        while true; do
            timeout 60 socat TCP-LISTEN:${port},reuseaddr,fork SYSTEM:"
                client_ip=\$(echo \$SOCAT_PEERADDR | cut -d: -f1);
                $handler \$client_ip
            " 2>/dev/null || sleep 1
        done
    elif command -v nc >/dev/null 2>&1; then
        while true; do
            # Try different nc variants
            timeout 30 nc -l -p "$port" -c "$handler" 2>/dev/null || \
            timeout 30 nc -l "$port" -e /bin/bash -c "$handler" 2>/dev/null || \
            { echo "nc variant not supported for port $port" && sleep 60; }
        done
    else
        log $LOG_ERROR "$DAEMON_NAME" "No socat or nc available for port $port"
    fi
}

# === Main Startup ===

log $LOG_INFO "$DAEMON_NAME" "Starting enhanced honeypot services..."

# Enhanced SSH honeypot (port 2222)
start_honeypot_service 2222 "fake_ssh_advanced" "SSH" &

# WordPress honeypot (port 8080)
start_honeypot_service 8080 "fake_wordpress" "WordPress" &

# MySQL honeypot (port 3306) - may need root
#start_honeypot_service 3306 "fake_mysql" "MySQL" &

# RDP honeypot (port 3389) - may need root  
#start_honeypot_service 3389 "fake_rdp" "RDP" &

# Alternative high ports (no root needed)
start_honeypot_service 13306 "fake_mysql" "MySQL-Alt" &
start_honeypot_service 13389 "fake_rdp" "RDP-Alt" &

# Keep daemon alive
while true; do
    db_heartbeat "$DAEMON_NAME"
    sleep 30
done
