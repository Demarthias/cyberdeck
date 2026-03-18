# 🛡️ CYBERDECK - Advanced Threat Detection System

A production-ready, daemon-based cybersecurity monitoring system for Termux and Linux environments.

## 🎯 Features

- **Real-time Network Monitoring** - Continuous connection scanning
- **Intelligent Threat Scoring** - ML-inspired adaptive threat detection
- **Automatic Containment** - Block/quarantine malicious IPs
- **Zero Collateral Damage** - Whitelisted local processes and IPs
- **Persistent Threat Intelligence** - SQLite-backed threat database
- **Live Cockpit HUD** - Real-time status in your terminal prompt
- **Production Architecture** - Proper error handling, logging, PID management

## 📋 Requirements

### Minimum
- Bash 4.0+
- SQLite3
- iproute2 (`ss` command)
- bc (basic calculator)

### Optional
- Root access (for iptables-based blocking)
- ZSH (for advanced cockpit HUD)

### Installation (Termux)
```bash
pkg install sqlite iproute2 bc -y
```

### Installation (Debian/Ubuntu)
```bash
apt install sqlite3 iproute2 bc -y
```

## 🚀 Quick Start

### 1. Install
```bash
cd ~/cyberdeck
chmod +x install.sh
./install.sh
```

### 2. Start
```bash
cd ~/cyberdeck
./start.sh
```

### 3. Check Status
```bash
cd ~/cyberdeck
bash healthcheck.sh
```

### 4. View Logs
```bash
tail -f ~/cyberdeck/logs/*.log
```

### 5. Stop
```bash
cd ~/cyberdeck
./stop.sh
```

## 🎛️ Configuration

Edit `~/cyberdeck/config/cyberdeck.conf` to customize:

```bash
# Threat thresholds
export THREAT_THRESHOLD_NOTIFY=5    # Yellow alert
export THREAT_THRESHOLD_BLOCK=8     # Auto-block

# Scan intervals
export SENSOR_INTERVAL=5            # Connection scan frequency
export SUPERVISOR_INTERVAL=10       # Health check frequency

# Firewall mode
export FIREWALL_MODE="APP_LAYER"    # or "IPTABLES" (requires root)

# Trusted IPs (never blocked)
export TRUSTED_IPS=("127.0.0.1" "192.168.1.100")
```

## 🏗️ Architecture

```
┌─────────────┐
│   SENSOR    │ ─────> Monitors network connections
└──────┬──────┘
       │
       v
┌─────────────┐
│ INTELLIGENCE│ ─────> Calculates threat scores
└──────┬──────┘
       │
       ├──────> FIREWALL (blocks IPs)
       ├──────> CONTAINMENT (quarantines)
       └──────> LOGGING (alerts)
       
SUPERVISOR ─────> Monitors all daemons
```

## 📊 Daemons

| Daemon | Purpose | PID File |
|--------|---------|----------|
| **Supervisor** | Keeps all daemons alive | `supervisor.pid` |
| **Sensor** | Network monitoring | `sensor.pid` |
| **Intelligence** | Threat scoring | `intel.pid` |
| **Firewall** | IP blocking | `firewall.pid` |
| **Containment** | Quarantine management | `containment.pid` |
| **Logging** | Alert aggregation | `logging.pid` |

## 🎨 Cockpit HUD

Add to your `.zshrc`:

```bash
source ~/cyberdeck/cockpit/cockpit.zsh

# Add status indicator to prompt
PROMPT='$(cyberdeck_prompt) %n@%m %~ %# '
```

### HUD Commands
```bash
cyberdeck-start       # Start all daemons
cyberdeck-stop        # Stop all daemons
cyberdeck-status      # Full health check
cyberdeck-logs        # Live log tail
cyberdeck-alerts      # Live alert feed
cyberdeck-threats     # Top 10 threats
cyberdeck_hud         # Full-screen HUD
```

## 🔍 Monitoring

### View Top Threats
```bash
sqlite3 ~/cyberdeck/config/threats.db \
  "SELECT ip, total_score, blocked FROM threats 
   WHERE total_score >= 5 
   ORDER BY total_score DESC LIMIT 10;"
```

### View Recent Connections
```bash
sqlite3 ~/cyberdeck/config/threats.db \
  "SELECT datetime(timestamp, 'unixepoch'), ip, port 
   FROM connections 
   ORDER BY timestamp DESC LIMIT 20;"
```

### View Alerts
```bash
sqlite3 ~/cyberdeck/config/threats.db \
  "SELECT datetime(timestamp, 'unixepoch'), alert_type, ip, score, message 
   FROM alerts 
   ORDER BY timestamp DESC LIMIT 20;"
```

## 🛠️ Troubleshooting

### Daemon Won't Start
```bash
# Check logs
cat ~/cyberdeck/logs/sensor.out
cat ~/cyberdeck/logs/intel.out

# Check permissions
ls -la ~/cyberdeck/pipes/
ls -la ~/cyberdeck/pids/

# Manually run daemon
bash ~/cyberdeck/sensors/sensor.sh
```

### No Threats Detected
```bash
# Check sensor is running
ps aux | grep sensor.sh

# Check connections being monitored
ss -tn | grep ESTAB

# Lower threshold for testing
nano ~/cyberdeck/config/cyberdeck.conf
# Set THREAT_THRESHOLD_NOTIFY=1
./stop.sh && ./start.sh
```

### Database Locked
```bash
# Check for hanging processes
fuser ~/cyberdeck/config/threats.db

# Kill if necessary
fuser -k ~/cyberdeck/config/threats.db

# Restart
./stop.sh && ./start.sh
```

## 🔒 Security Notes

### What Gets Blocked
- External IPs with threat score >= `THREAT_THRESHOLD_BLOCK`
- Connections from previously blocked IPs
- High-frequency connection attempts
- Suspicious port activity

### What NEVER Gets Blocked
- Local IPs (127.*, 192.168.*, 10.*, etc.)
- IPs in `TRUSTED_IPS` config
- Whitelisted processes (bash, zsh, termux, sshd, etc.)

### Firewall Modes

**APP_LAYER** (default, no root required)
- Kills connections at application level
- Maintains blacklist
- Works in Termux without root

**IPTABLES** (requires root)
- Kernel-level blocking
- More efficient
- Requires: `sudo` or `su`

## 📈 Performance

### Resource Usage (Typical)
- CPU: <1% per daemon
- RAM: ~5MB total for all daemons
- Disk: <100MB (logs + database)

### Battery Impact (Mobile)
- Light: 1-2% per hour (default settings)
- Can enable `ENABLE_POWER_SAVE=true` for lower impact

## 🧪 Testing

```bash
# Simulate external connection (from another device)
# The system will detect and score it

# Monitor in real-time
tail -f ~/cyberdeck/logs/sensor.log
tail -f ~/cyberdeck/logs/intel.log

# Check if threat detected
bash healthcheck.sh
```

## 📚 Advanced Usage

### Custom Threat Scoring
Edit `~/cyberdeck/intelligence/intel.sh` to add custom heuristics:
- GeoIP-based scoring
- Reputation list checks
- ML model integration
- Custom port profiles

### Integration with Other Tools
```bash
# Export threats to fail2ban
sqlite3 ~/cyberdeck/config/threats.db \
  "SELECT ip FROM threats WHERE blocked=1;" > /etc/fail2ban/threats.txt

# Send alerts to external service
# Edit logging.sh to add webhook/API calls
```

## 🆘 Support

### Check System Health
```bash
bash ~/cyberdeck/healthcheck.sh
```

### Reset System
```bash
./stop.sh
rm -f ~/cyberdeck/pids/*
rm -f ~/cyberdeck/pipes/*
./start.sh
```

### Full Reinstall
```bash
./stop.sh
cd ~
mv cyberdeck cyberdeck_backup
# Re-install from scratch
```

## 📜 License

MIT License - Free to use and modify

## 🤝 Contributing

This is a production-ready foundation. Customize and extend as needed:
- Add honeypot services
- Integrate ML models
- Add UI dashboard
- Connect to SIEM systems

---

**Made for operators who demand stability, safety, and power.**
