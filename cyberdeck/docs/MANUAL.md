# 📖 CYBERDECK SYSTEM MANUAL

## Table of Contents
1. [Architecture](#architecture)
2. [Daemon Reference](#daemon-reference)
3. [Configuration](#configuration)
4. [Database Schema](#database-schema)
5. [API Reference](#api-reference)
6. [Troubleshooting](#troubleshooting)

---

## Architecture

### System Design

```
External Connection
        ↓
   ┌─────────┐
   │ SENSOR  │ → Detects connection, assigns initial metrics
   └────┬────┘
        ↓ (sends to intel_queue)
   ┌─────────┐
   │  INTEL  │ → Calculates threat score, determines action
   └────┬────┘
        ↓ (sends to action queues)
   ┌────┴──────┬───────────┬──────────┐
   ↓           ↓           ↓          ↓
FIREWALL  CONTAINMENT  LOGGING   COCKPIT
```

### Communication Model

**FIFO Pipes** (Named Pipes)
- `intel_queue` - Sensor → Intelligence
- `firewall_queue` - Intelligence → Firewall
- `containment_queue` - Intelligence → Containment
- `cockpit_queue` - Intelligence → Logging → Cockpit

**SQLite Database**
- Persistent threat intelligence
- Connection history
- Alert logs
- System statistics

---

## Daemon Reference

### Supervisor (`supervisor.sh`)

**Purpose**: Master daemon that monitors and restarts all other daemons

**Features**:
- Health checking via heartbeat monitoring
- Automatic daemon restart on failure
- Log rotation
- Database cleanup

**Configuration**:
- `SUPERVISOR_INTERVAL` - Health check frequency (default: 10s)
- `HEARTBEAT_TIMEOUT` - Max age before daemon considered dead (default: 30s)

**Logs**: `logs/supervisor.out`

---

### Sensor (`sensors/sensor.sh`)

**Purpose**: Network connection monitoring

**Monitored Data**:
- Active TCP connections (via `ss` or `netstat`)
- Remote IP addresses
- Remote ports
- Connection frequency

**Process**:
1. Scans for ESTABLISHED connections
2. Filters out local IPs
3. Tracks connection count per IP
4. Sends to intelligence layer

**Configuration**:
- `SENSOR_INTERVAL` - Scan frequency (default: 5s)

**Logs**: `logs/sensor.log`, `logs/sensor.out`

**Database Tables Used**:
- `connections` - Insert
- `stats` - Update

---

### Intelligence (`intelligence/intel.sh`)

**Purpose**: Threat scoring and decision engine

**Threat Scoring Algorithm**:

```
Base Score: 1 (any external connection)

+ Port-based scoring:
  - Suspicious ports (23, 21, etc.): +2
  - High-risk ports (3389, 5900, etc.): +3

+ Frequency scoring:
  - If connections > CONN_FREQ_WARN: + (count * 0.5)

+ History scoring:
  - Previously blocked IP: +5
  - Historical threat score: + accumulated

Total → Action:
  - < 5: LOG only
  - 5-7: NOTIFY (yellow alert)
  - >= 8: BLOCK (red alert)
```

**Configuration**:
- `THREAT_THRESHOLD_NOTIFY` - Alert threshold (default: 5)
- `THREAT_THRESHOLD_BLOCK` - Block threshold (default: 8)
- `SCORE_SUSPICIOUS_PORT` - Points for suspicious port (default: 2)
- `SCORE_HIGH_RISK_PORT` - Points for high-risk port (default: 3)
- `SCORE_FREQ_MULTIPLIER` - Frequency multiplier (default: 0.5)
- `SCORE_PREVIOUSLY_BLOCKED` - Points for repeat offender (default: 5)
- `INTEL_INTERVAL` - Processing frequency (default: 2s)

**Logs**: `logs/intel.log`, `logs/intel.out`

**Database Tables Used**:
- `threats` - Insert/Update
- `alerts` - Insert
- `actions` - Insert
- `stats` - Update

---

### Firewall (`firewall/firewall.sh`)

**Purpose**: IP-level blocking

**Modes**:

1. **APP_LAYER** (default, no root required)
   - Maintains blacklist file
   - Kills active connections from blocked IPs
   - Works in Termux without root

2. **IPTABLES** (requires root)
   - Kernel-level blocking via iptables
   - More efficient
   - Requires `sudo` or running as root

**Safety Features**:
- **Never blocks local IPs** (127.*, 192.168.*, 10.*)
- **Never blocks trusted IPs** (from TRUSTED_IPS config)
- **Validates all IP addresses**
- **Logs all block attempts**

**Configuration**:
- `FIREWALL_MODE` - "APP_LAYER" or "IPTABLES" (default: APP_LAYER)
- `FIREWALL_INTERVAL` - Check frequency (default: 1s)

**Files**:
- `config/blocked_ips.txt` - Current blacklist

**Logs**: `logs/firewall.log`, `logs/firewall.out`

---

### Containment (`containment/containment.sh`)

**Purpose**: Process quarantine and isolation

**Features**:
- Creates detailed quarantine records
- Logs connection history for blocked IPs
- Never touches protected processes

**Protected Processes** (never killed):
- bash, zsh, sh
- termux
- sshd, systemd, init
- All cyberdeck daemons

**Quarantine Record** (`quarantine/<ip>_<timestamp>.log`):
```
=== QUARANTINE RECORD ===
IP: x.x.x.x
Threat Score: 10
Timestamp: 2024-...
Reason: ...

=== CONNECTION HISTORY ===
[timestamp] [port] [protocol]
...
```

**Configuration**:
- `CONTAINMENT_INTERVAL` - Check frequency (default: 2s)

**Logs**: `logs/containment.log`, `logs/containment.out`

---

### Logging (`logging/logging.sh`)

**Purpose**: Alert aggregation and cockpit updates

**Features**:
- Aggregates alerts from all daemons
- Maintains cockpit alert file (last 50 alerts)
- Updates system statistics

**Files**:
- `logs/cockpit_alerts.txt` - Live alert feed

**Configuration**:
- None (runs continuously)

**Logs**: `logs/logging.log`, `logs/logging.out`

---

## Configuration

### Main Config File: `config/cyberdeck.conf`

```bash
# Base directory
export CYBERDECK_HOME="${HOME}/cyberdeck"

# Logging
export LOG_LEVEL=1  # 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR, 4=CRITICAL
export LOG_RETENTION_DAYS=7
export THREAT_RETENTION_DAYS=30

# Threat thresholds
export THREAT_THRESHOLD_NOTIFY=5
export THREAT_THRESHOLD_BLOCK=8

# Daemon intervals (seconds)
export SENSOR_INTERVAL=5
export INTEL_INTERVAL=2
export FIREWALL_INTERVAL=1
export CONTAINMENT_INTERVAL=2
export SUPERVISOR_INTERVAL=10

# Trusted IPs (whitelist)
export TRUSTED_IPS=(
    "127.0.0.1"
    "::1"
)

# Suspicious ports
export SUSPICIOUS_PORTS=("23" "21" "135" "445" "1433" "3306" "5432")

# High-risk ports
export HIGH_RISK_PORTS=("3389" "5900" "22")

# Threat scoring
export SCORE_SUSPICIOUS_PORT=2
export SCORE_HIGH_RISK_PORT=3
export SCORE_FREQ_MULTIPLIER=0.5
export SCORE_NEW_IP=1
export SCORE_PREVIOUSLY_BLOCKED=5

# Firewall mode
export FIREWALL_MODE="APP_LAYER"  # or "IPTABLES"
export REQUIRE_ROOT=false

# Cockpit
export COCKPIT_ENABLED=true
```

---

## Database Schema

### `threats` Table
```sql
CREATE TABLE threats (
    ip TEXT PRIMARY KEY,
    total_score INTEGER DEFAULT 0,
    first_seen INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    blocked INTEGER DEFAULT 0,
    block_time INTEGER,
    connection_count INTEGER DEFAULT 0,
    last_ports TEXT,
    notes TEXT
);
```

### `connections` Table
```sql
CREATE TABLE connections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    ip TEXT NOT NULL,
    port INTEGER,
    protocol TEXT,
    state TEXT,
    process_name TEXT
);
```

### `alerts` Table
```sql
CREATE TABLE alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    alert_type TEXT NOT NULL,  -- 'BLOCK', 'WARNING', 'INFO'
    ip TEXT,
    score INTEGER,
    message TEXT,
    acknowledged INTEGER DEFAULT 0
);
```

### `actions` Table
```sql
CREATE TABLE actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    action_type TEXT NOT NULL,  -- 'BLOCK', 'QUARANTINE', 'ALERT'
    ip TEXT,
    daemon TEXT NOT NULL,
    details TEXT,
    success INTEGER DEFAULT 1
);
```

### `stats` Table
```sql
CREATE TABLE stats (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated INTEGER
);
```

---

## API Reference

### Common Library Functions (`lib/common.sh`)

```bash
# Logging
log <level> <daemon_name> <message>
  # Levels: LOG_DEBUG, LOG_INFO, LOG_WARN, LOG_ERROR, LOG_CRITICAL

# Validation
validate_ip <ip>                 # Returns 0 if valid IPv4
is_local_ip <ip>                 # Returns 0 if local/trusted

# Pipes
init_pipe <pipe_name>            # Creates and secures FIFO
read_pipe_safe <pipe> <timeout> <varnames...>  # Non-blocking read
send_to_pipe <pipe> <message>    # Non-blocking write

# Database
exec_sql <query>                 # Execute SQL
get_threat_score <ip>            # Get threat score for IP
update_threat_score <ip> <score> # Update threat score
mark_blocked <ip>                # Mark IP as blocked
is_blocked <ip>                  # Check if IP is blocked

# Health
update_heartbeat <daemon_name>   # Update daemon heartbeat
check_daemon_health <daemon> [max_age]  # Check if healthy

# Process
init_pidfile <daemon_name>       # Create PID file
daemon_cleanup <daemon_name>     # Clean up on exit
```

---

## Troubleshooting

### Common Issues

#### 1. Daemons Keep Crashing

**Check logs**:
```bash
cat ~/cyberdeck/logs/sensor.out
cat ~/cyberdeck/logs/intel.out
```

**Common causes**:
- Missing dependencies (sqlite3, ss, bc)
- Permission issues on pipes
- Database locked

**Solution**:
```bash
# Install dependencies
pkg install sqlite iproute2 bc -y

# Fix permissions
chmod 600 ~/cyberdeck/pipes/*
chmod 700 ~/cyberdeck/pids

# Kill database locks
fuser -k ~/cyberdeck/config/threats.db

# Restart
./stop.sh && ./start.sh
```

---

#### 2. No Threats Detected

**Verify sensor is working**:
```bash
# Check for active connections
ss -tn | grep ESTAB

# Check sensor log
tail -f ~/cyberdeck/logs/sensor.log
```

**If no connections shown**:
- You may not have external connections
- Lower thresholds for testing

**Solution**:
```bash
# Edit config
nano ~/cyberdeck/config/cyberdeck.conf

# Set to detect everything
THREAT_THRESHOLD_NOTIFY=1
THREAT_THRESHOLD_BLOCK=100  # Very high to avoid actual blocking

# Restart
./stop.sh && ./start.sh
```

---

#### 3. Too Many False Positives

**Symptoms**:
- Legitimate IPs being blocked
- Too many yellow alerts

**Solution**:
```bash
# Increase thresholds
nano ~/cyberdeck/config/cyberdeck.conf

# More conservative
THREAT_THRESHOLD_NOTIFY=7
THREAT_THRESHOLD_BLOCK=12

# Add trusted IPs
TRUSTED_IPS=("127.0.0.1" "your.trusted.ip" "192.168.1.0/24")

# Restart
./stop.sh && ./start.sh
```

---

#### 4. Database "Locked" Errors

**Cause**: Multiple processes trying to write simultaneously

**Solution**:
```bash
# Check what's using it
fuser ~/cyberdeck/config/threats.db

# Kill if necessary
fuser -k ~/cyberdeck/config/threats.db

# Restart system
./stop.sh && sleep 2 && ./start.sh
```

---

#### 5. High CPU Usage

**Check which daemon**:
```bash
ps aux | grep -E "(sensor|intel|firewall)" | grep -v grep
```

**Solutions**:
```bash
# Increase intervals (reduce frequency)
nano ~/cyberdeck/config/cyberdeck.conf

# Less frequent scanning
SENSOR_INTERVAL=10     # Default: 5
INTEL_INTERVAL=5       # Default: 2

# Enable power save mode
ENABLE_POWER_SAVE=true

# Restart
./stop.sh && ./start.sh
```

---

### Advanced Debugging

#### Enable Debug Logging

```bash
nano ~/cyberdeck/config/cyberdeck.conf

# Set log level to DEBUG
LOG_LEVEL=0

./stop.sh && ./start.sh

# Watch debug logs
tail -f ~/cyberdeck/logs/*.log
```

#### Manual Daemon Testing

```bash
# Test sensor directly
export CYBERDECK_HOME=~/cyberdeck
bash ~/cyberdeck/sensors/sensor.sh

# Test intelligence
bash ~/cyberdeck/intelligence/intel.sh

# etc.
```

#### Inspect Database

```bash
sqlite3 ~/cyberdeck/config/threats.db

# Show all threats
SELECT * FROM threats ORDER BY total_score DESC;

# Show recent connections
SELECT datetime(timestamp, 'unixepoch'), ip, port 
FROM connections 
ORDER BY timestamp DESC 
LIMIT 20;

# Show alerts
SELECT datetime(timestamp, 'unixepoch'), alert_type, ip, message 
FROM alerts 
ORDER BY timestamp DESC;
```

---

## Performance Tuning

### Battery Life Optimization (Mobile)

```bash
# Reduce scan frequency
SENSOR_INTERVAL=10       # Default: 5
INTEL_INTERVAL=5         # Default: 2
SUPERVISOR_INTERVAL=30   # Default: 10

# Enable power save
ENABLE_POWER_SAVE=true
```

### Maximum Security

```bash
# Aggressive monitoring
SENSOR_INTERVAL=2
THREAT_THRESHOLD_BLOCK=5  # Block faster

# More sensitive scoring
SCORE_SUSPICIOUS_PORT=3
SCORE_HIGH_RISK_PORT=5

# Enable iptables (if root)
FIREWALL_MODE="IPTABLES"
```

### Low-Resource Systems

```bash
# Minimal overhead
SENSOR_INTERVAL=15
INTEL_INTERVAL=10
LOG_LEVEL=2  # WARN and above only
LOG_RETENTION_DAYS=3
```

---

**For more info, see README.md and QUICKSTART.md**
