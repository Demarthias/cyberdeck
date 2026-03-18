#!/bin/bash
# Honeypot Daemon - Deception and intelligence gathering

DAEMON_NAME="honeypot"
CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"

# Source shared library
source "${CYBERDECK_HOME}/lib/common.sh"

# Initialize
init_pidfile "$DAEMON_NAME"
trap "daemon_cleanup \"$DAEMON_NAME\"" EXIT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 130" INT
trap "daemon_cleanup \"$DAEMON_NAME\"; exit 143" TERM

log $LOG_INFO "$DAEMON_NAME" "Honeypot daemon starting..."

if [[ "$HONEYPOT_ENABLED" != "true" ]]; then
    log $LOG_INFO "$DAEMON_NAME" "Honeypots disabled in config"
    exit 0
fi

# Honeypot log directory
HONEYPOT_LOG_DIR="${CYBERDECK_HOME}/logs/honeypots"
mkdir -p "$HONEYPOT_LOG_DIR"

# === Fake Service Handlers ===

fake_ssh_handler() {
    local client_ip=$1
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local log_file="${HONEYPOT_LOG_DIR}/ssh_${client_ip}_$(date +%s).log"
    
    echo "$timestamp - SSH connection from $client_ip" >> "$log_file"
    
    # Send fake SSH banner
    echo "SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.1"
    
    # Wait for authentication attempt
    read -t 10 auth_attempt
    echo "$timestamp - Auth attempt: $auth_attempt" >> "$log_file"
    
    # Log to database
    exec_sql "INSERT INTO alerts (timestamp, alert_type, ip, score, message)
              VALUES ($(date +%s), 'WARNING', '$(sanitize_sql "$client_ip")', 0, 'SSH honeypot connection');"

    # Increment threat score
    update_threat_score "$client_ip" 3
    
    # Send fake failure
    echo "Permission denied (publickey,password)."
    
    log $LOG_INFO "$DAEMON_NAME" "SSH honeypot hit from $client_ip"
}

fake_ftp_handler() {
    local client_ip=$1
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local log_file="${HONEYPOT_LOG_DIR}/ftp_${client_ip}_$(date +%s).log"
    
    echo "$timestamp - FTP connection from $client_ip" >> "$log_file"
    
    # Send FTP banner
    echo "220 ProFTPD Server (Debian) [::ffff:$client_ip]"
    
    # Wait for commands
    while read -t 10 command; do
        echo "$timestamp - FTP command: $command" >> "$log_file"
        
        case $command in
            USER*)
                echo "331 Password required"
                ;;
            PASS*)
                echo "530 Login incorrect"
                exec_sql "INSERT INTO alerts (timestamp, alert_type, ip, score, message)
                          VALUES ($(date +%s), 'WARNING', '$(sanitize_sql "$client_ip")', 0, 'FTP login attempt');"
                break
                ;;
            QUIT)
                echo "221 Goodbye"
                break
                ;;
            *)
                echo "500 Unknown command"
                ;;
        esac
    done
    
    update_threat_score "$client_ip" 4
    log $LOG_INFO "$DAEMON_NAME" "FTP honeypot hit from $client_ip"
}

fake_http_handler() {
    local client_ip=$1
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local log_file="${HONEYPOT_LOG_DIR}/http_${client_ip}_$(date +%s).log"
    
    # Read HTTP request
    local request=""
    while read -t 5 line; do
        request+="$line"$'\n'
        [[ -z "$line" ]] && break
    done
    
    echo "$timestamp - HTTP request from $client_ip" >> "$log_file"
    echo "$request" >> "$log_file"
    
    # Send fake HTTP response
    cat <<EOF
HTTP/1.1 200 OK
Server: Apache/2.4.41 (Ubuntu)
Content-Type: text/html
Content-Length: 137

<html>
<head><title>Welcome</title></head>
<body>
<h1>Server Status: Online</h1>
<p>Admin login: <a href="/admin">here</a></p>
</body>
</html>
EOF
    
    # Check for suspicious patterns
    if echo "$request" | grep -iE '(admin|wp-admin|phpmyadmin|\.php|\.asp)' >/dev/null; then
        update_threat_score "$client_ip" 3
        exec_sql "INSERT INTO alerts (timestamp, alert_type, ip, score, message)
                  VALUES ($(date +%s), 'WARNING', '$(sanitize_sql "$client_ip")', 0, 'Suspicious HTTP request pattern');"
        log $LOG_WARN "$DAEMON_NAME" "Suspicious HTTP request from $client_ip"
    fi

    log $LOG_INFO "$DAEMON_NAME" "HTTP honeypot hit from $client_ip"
}

# === Honeypot Services ===

start_honeypot() {
    local port=$1
    local handler=$2
    
    log $LOG_INFO "$DAEMON_NAME" "Starting honeypot on port $port ($handler)"
    
    # Use ncat if available, otherwise nc
    local nc_cmd="nc"
    if command -v ncat >/dev/null 2>&1; then
        nc_cmd="ncat"
    fi
    
    # Start listening (in background per connection)
    while true; do
        # Listen for connection
        if command -v socat >/dev/null 2>&1; then
            # socat is more reliable
            socat TCP-LISTEN:${port},reuseaddr,fork SYSTEM:"
                client_ip=\$(echo \$SOCAT_PEERADDR | cut -d: -f1);
                $handler \$client_ip
            " 2>/dev/null
        else
            # Fallback to nc
            $nc_cmd -l -p "$port" -c "
                read -r line;
                client_ip=\$(echo \$line | awk '{print \$1}');
                $handler \$client_ip
            " 2>/dev/null
        fi
        
        # Brief pause between connections
        sleep 1
    done
}

# === Main Loop ===

# Start honeypot services for configured ports
for port in "${HONEYPOT_PORTS[@]}"; do
    case $port in
        2222|22)
            start_honeypot "$port" "fake_ssh_handler" &
            ;;
        21)
            start_honeypot "$port" "fake_ftp_handler" &
            ;;
        80|8080|8000)
            start_honeypot "$port" "fake_http_handler" &
            ;;
        *)
            log $LOG_WARN "$DAEMON_NAME" "No handler for port $port"
            ;;
    esac
done

# Keep daemon alive and update heartbeat
while true; do
    update_heartbeat "$DAEMON_NAME"
    sleep 30
done
