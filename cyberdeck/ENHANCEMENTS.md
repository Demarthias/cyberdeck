# 🚀 CYBERDECK ENHANCEMENTS GUIDE

**Advanced Features: Threat Intelligence, Machine Learning, Packet Inspection & More**

---

## 📦 What's Included

### **TIER 1: Essential Enhancements** (Quick Wins)

1. **External Threat Intelligence**
   - AbuseIPDB integration
   - AlienVault OTX integration  
   - Tor exit node detection
   - Automatic threat score boosting

2. **Webhook Alerts**
   - Discord notifications
   - Slack notifications
   - Custom webhook support
   - Configurable severity filtering

### **TIER 2: Advanced Features** (Power User)

3. **Enhanced Honeypots**
   - Cowrie-style SSH honeypot
   - Fake WordPress login
   - Fake MySQL service
   - Fake RDP service
   - Credential capture

4. **TUI Dashboard**
   - Interactive terminal interface
   - Real-time status monitoring
   - Log viewing
   - IP blocking/unblocking
   - Statistics dashboard

5. **Automated Playbooks**
   - Rule-based automated responses
   - Conditional actions
   - Custom triggers
   - Multi-stage workflows

### **TIER 3: Experimental** (Bleeding Edge)

6. **Machine Learning Anomaly Detection**
   - Statistical baseline analysis
   - Port behavior profiling
   - IP behavior profiling
   - Time-based anomaly detection
   - Automatic retraining

7. **Packet Inspection**
   - Deep packet inspection (DPI)
   - Protocol fingerprinting
   - Exploit signature detection
   - Tool detection (nmap, Metasploit, etc.)
   - Packet capture for high threats

8. **Distributed Network Coordination**
   - Multi-device threat sharing
   - Consensus-based threat validation
   - Coordinated blocking
   - Peer-to-peer or master/slave modes

---

## 🎯 Quick Start

### Installation

```bash
# Prerequisites
pkg install sqlite curl bc dialog socat tcpdump -y

# Install enhancements
cd ~/cyberdeck
bash install_enhancements.sh
```

### Starting Enhanced Cyberdeck

```bash
# Start all (base + enhancements)
bash ~/cyberdeck/start_enhanced.sh

# Or start selectively
cyberdeck start  # Base only
nohup bash ~/cyberdeck/enhancements/threat_intel.sh &
nohup bash ~/cyberdeck/enhancements/webhook_alerts.sh &
```

### Launch TUI Dashboard

```bash
bash ~/cyberdeck/enhancements/tui_dashboard.sh
```

---

## 📚 Feature Details

### 1️⃣ Threat Intelligence

**What it does:**
- Checks IPs against AbuseIPDB (abuse reports database)
- Queries AlienVault OTX (open threat exchange)
- Detects Tor exit nodes
- Automatically boosts threat scores for known malicious IPs

**Configuration:**

```bash
# Edit ~/cyberdeck/config/enhancements.conf

# Get free API key from https://www.abuseipdb.com/api
ABUSEIPDB_API_KEY="your_key_here"

# Get free API key from https://otx.alienvault.com/
OTX_API_KEY="your_key_here"

# Tor detection (no API needed)
TOR_DETECTION_ENABLED=true
```

**How it works:**
1. Monitors recent threats from database
2. Queries external APIs (rate-limited to avoid abuse)
3. Caches results for 24 hours
4. Adds +3 to +5 threat score based on reputation
5. Logs all findings

**Output:**
```
[INFO] Threat boost for 203.0.113.42: +5 (abuseipdb,tor_exit)
```

---

### 2️⃣ Webhook Alerts

**What it does:**
- Sends real-time alerts to Discord, Slack, or custom webhooks
- Filters by severity (yellow/red)
- Rate-limits to prevent spam
- Rich formatted notifications

**Setup Discord:**

1. Create webhook in Discord server settings
2. Copy webhook URL
3. Add to config:
```bash
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."
```

**Setup Slack:**

1. Create incoming webhook in Slack workspace
2. Copy webhook URL
3. Add to config:
```bash
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
```

**Custom Webhooks:**
```bash
CUSTOM_WEBHOOK_URL="https://your-server.com/webhook"
```

Sends JSON:
```json
{
  "severity": "RED",
  "ip": "203.0.113.42",
  "message": "Port scan detected",
  "timestamp": "2025-03-13T10:30:00Z",
  "source": "cyberdeck"
}
```

---

### 3️⃣ Enhanced Honeypots

**What it does:**
- Realistic fake services to trap attackers
- Logs all connection attempts
- Captures credentials
- Detects attack tools

**Available Honeypots:**

| Service | Port | Captures |
|---------|------|----------|
| SSH | 2222 | Login attempts, usernames |
| WordPress | 8080 | Admin logins, usernames/passwords |
| MySQL | 13306 | Connection attempts |
| RDP | 13389 | Connection attempts |

**Logs Location:**
```bash
~/cyberdeck/logs/honeypots/
  ssh_203.0.113.42_1234567890.log
  wordpress_198.51.100.7_1234567891.log
```

**Example Log:**
```
[2025-03-13 10:30:45] SSH connection from 203.0.113.42
[2025-03-13 10:30:47] Auth attempt 1: user=root pass=password123
[2025-03-13 10:30:49] Auth attempt 2: user=admin pass=admin
```

---

### 4️⃣ TUI Dashboard

**What it does:**
- Full-screen interactive terminal interface
- Navigate with arrow keys and Enter
- Real-time updates
- All cyberdeck functions in one place

**Launch:**
```bash
bash ~/cyberdeck/enhancements/tui_dashboard.sh
```

**Features:**
- System status overview
- Top threats list
- Recent alerts timeline
- Daemon logs viewer
- Statistics dashboard
- Block/unblock IPs
- Daemon management
- Health checks

**Keyboard Navigation:**
- Arrow keys: Navigate menu
- Enter: Select option
- Numbers: Quick select
- 0/ESC: Exit

---

### 5️⃣ Automated Playbooks

**What it does:**
- Automatically responds to detected threats
- Rule-based "if X then Y" logic
- Multi-condition triggers
- Customizable actions

**Playbook Format:**
```
TRIGGER|CONDITION|ACTION|PARAMETERS
```

**Example Playbooks:**

```bash
# In ~/cyberdeck/playbooks/rules.conf

# Block after scanning 10+ ports
port_scan|ports_gt_10|block_ip|

# Boost score for WordPress attacks
wordpress_hit|always|increase_score|4

# Tag Tor users
tor_exit|always|tag|tor_user

# Block high-frequency connections
high_frequency|connections_gt_50|block_ip|

# Capture SSH brute force
ssh_honeypot|attempts_gt_3|capture_credentials|
```

**Available Triggers:**
- `port_scan` - Multiple ports accessed
- `ssh_honeypot` - SSH honeypot hits
- `wordpress_hit` - WordPress attack
- `high_frequency` - Many connections
- `credential_stuffing` - Brute force detected
- `tor_exit` - Tor exit node

**Available Actions:**
- `block_ip` - Block the IP
- `increase_score` - Add to threat score
- `deploy_honeypot` - Start honeypot on port
- `capture_credentials` - Log attempts
- `tag` - Add tag to IP
- `alert_webhook` - Send webhook alert

---

### 6️⃣ Machine Learning Anomaly Detection

**What it does:**
- Learns normal behavior patterns
- Detects statistical anomalies
- Builds baselines per port, IP, time
- Auto-adapts to your traffic

**How it Works:**

1. **Training Phase** (24 hours)
   - Observes normal traffic patterns
   - Calculates mean and standard deviation
   - Builds behavioral profiles

2. **Detection Phase**
   - Compares current behavior to baseline
   - Flags anomalies >2.5 standard deviations
   - Adds +2 to +3 threat score

**Anomaly Types Detected:**

| Type | What it Detects |
|------|----------------|
| Port anomaly | Unusual traffic volume on specific port |
| IP behavior | IP accessing unexpected ports |
| Time anomaly | Unusual connection count for time of day |
| Pattern anomaly | Regular/scripted connection patterns |

**Configuration:**
```bash
ML_ANOMALY_THRESHOLD=2.5  # Sensitivity (lower = more sensitive)
ML_TRAINING_PERIOD_HOURS=24
```

**Output:**
```
[WARN] IP 203.0.113.42 behavior anomaly: new port 8443 (typical: 80,443)
[WARN] Port 22 anomaly detected: z-score=3.2 (count=150, mean=45)
```

---

### 7️⃣ Packet Inspection

**What it does:**
- Deep packet inspection (DPI)
- Protocol identification
- Exploit signature matching
- Attack tool detection
- Packet capture for forensics

**Requires:**
- `tcpdump` (for packet capture)
- Root access (for kernel-level capture)
- Falls back to connection analysis without root

**Signatures Detected:**
- SQL injection attempts
- XSS (cross-site scripting)
- Path traversal
- Shell injection
- NOP sleds (shellcode)
- File inclusion
- Command injection

**Tool Detection:**
- nmap, masscan, zmap
- Metasploit framework
- Nikto, dirb, dirbuster
- Custom user agents

**Packet Capture:**
- Automatically captures high-threat IPs (score >= 7)
- 30-second capture window
- Stored in `~/cyberdeck/pcaps/`
- Can analyze with Wireshark later

**Example:**
```
[WARN] Threat signature detected from 203.0.113.42: SQL_INJECTION
[WARN] Metasploit detected from 198.51.100.7
[INFO] Capturing packets from 203.0.113.42 for 30s
```

---

### 8️⃣ Distributed Network Coordination

**What it does:**
- Shares threat intelligence across multiple cyberdeck instances
- Coordinated blocking
- Consensus-based threat validation
- Works in peer-to-peer or master/slave modes

**Use Cases:**
- Multiple Termux devices in your network
- Coordinated defense across phones/tablets
- Shared threat intelligence within team

**Modes:**

**Peer Mode** (Equal nodes):
```bash
CYBERDECK_NETWORK_MODE="peer"
CYBERDECK_PEERS="192.168.1.10,192.168.1.11"
```

**Master/Slave Mode:**
```bash
# On master
CYBERDECK_NETWORK_MODE="master"

# On slaves
CYBERDECK_NETWORK_MODE="slave"
CYBERDECK_MASTER="192.168.1.100"
```

**How it Works:**
1. Each node detects threats locally
2. High-threat IPs (score >= 7) shared with peers
3. Peers apply reduced score (trust factor 0.5)
4. Multiple nodes reporting same IP = consensus boost
5. Coordinated blocks propagate automatically

**Protocol:**
- UDP broadcast on configurable port (default 9999)
- Simple JSON message format
- Automatic peer discovery
- Rate-limited syncing

**Security:**
- Local network only (no internet exposure)
- Trust factor prevents false positive amplification
- Node ID tracking prevents loops

---

## 🔧 Configuration Reference

### Main Config Files

**~/cyberdeck/config/cyberdeck.conf** - Base system
**~/cyberdeck/config/enhancements.conf** - Enhancement features

### Key Settings

```bash
# Threat Intelligence
ABUSEIPDB_API_KEY=""  # Free tier: 1000 requests/day
OTX_API_KEY=""        # Free tier: unlimited

# Webhooks
DISCORD_WEBHOOK_URL=""
SLACK_WEBHOOK_URL=""
WEBHOOK_MIN_SEVERITY="YELLOW"  # or "RED"

# Honeypots
ENHANCED_HONEYPOTS_ENABLED=true
HONEYPOT_SSH_PORT=2222
HONEYPOT_WORDPRESS_PORT=8080

# Playbooks
PLAYBOOKS_ENABLED=true
PLAYBOOKS_FILE="${CYBERDECK_HOME}/playbooks/rules.conf"

# Machine Learning
ML_ANOMALY_ENABLED=true
ML_ANOMALY_THRESHOLD=2.5

# Packet Inspection
PACKET_INSPECTION_ENABLED=true
AUTO_CAPTURE_THRESHOLD=7

# Distributed
DISTRIBUTED_ENABLED=false  # Set to true to enable
CYBERDECK_NETWORK_MODE="peer"
CYBERDECK_PEERS=""
```

---

## 📊 Monitoring & Logs

### Log Locations

```bash
~/cyberdeck/logs/
  threat_intel_output.log    # Threat intelligence
  webhook_output.log         # Webhook alerts
  honeypots_output.log       # Enhanced honeypots
  playbooks_output.log       # Automated actions
  ml_output.log              # ML detections
  packet_output.log          # DPI findings
  distributed_output.log     # Network sync
```

### Viewing Logs

```bash
# Real-time tail
tail -f ~/cyberdeck/logs/threat_intel_output.log

# Search for specific IP
grep "203.0.113.42" ~/cyberdeck/logs/*.log

# View ML detections only
grep "anomaly" ~/cyberdeck/logs/ml_output.log
```

### Database Queries

```bash
# Threat intel sources
sqlite3 ~/cyberdeck/cache/reputation_cache.db \
  "SELECT ip, source, confidence FROM reputation WHERE is_malicious=1;"

# ML baselines
sqlite3 ~/cyberdeck/cache/ml/baseline.db \
  "SELECT * FROM port_baselines;"
```

---

## 🚨 Troubleshooting

### Threat Intel Not Working

```bash
# Check API keys
grep "API_KEY" ~/cyberdeck/config/enhancements.conf

# Test AbuseIPDB manually
curl -G https://api.abuseipdb.com/api/v2/check \
  -H "Key: YOUR_KEY" \
  --data-urlencode "ipAddress=8.8.8.8"

# Check daemon
tail -f ~/cyberdeck/logs/threat_intel_output.log
```

### Webhooks Not Sending

```bash
# Test Discord webhook
curl -X POST -H "Content-Type: application/json" \
  -d '{"content":"Test from cyberdeck"}' \
  YOUR_DISCORD_WEBHOOK_URL

# Check logs
tail -f ~/cyberdeck/logs/webhook_output.log
```

### TUI Dashboard Won't Start

```bash
# Install dialog
pkg install dialog -y

# Check for errors
bash -x ~/cyberdeck/enhancements/tui_dashboard.sh
```

### ML Not Detecting Anomalies

```bash
# Check if enough training data
sqlite3 ~/cyberdeck/cyberdeck.db \
  "SELECT COUNT(*) FROM connections;"

# Need at least 100+ connections for good baselines
# Wait 24 hours for initial training period
```

---

## 💡 Best Practices

### 1. Start with Tier 1
- Get threat intel working first
- Set up webhooks for alerts
- Master the basics before advanced features

### 2. Use TUI Dashboard
- Easier than command line
- Real-time visibility
- Quick actions

### 3. Configure API Keys
- Free tiers are sufficient
- Dramatically improves accuracy
- Worth the 5 minutes to set up

### 4. Tune Playbooks Gradually
- Start conservative
- Monitor false positives
- Adjust thresholds as needed

### 5. Let ML Train
- Wait 24-48 hours before trusting anomaly detection
- More data = better baselines
- Retrain after major network changes

### 6. Review Honeypot Logs
- Check daily for interesting attempts
- Look for patterns
- Share findings (educational)

---

## 🎯 Use Case Examples

### Home Network Protection

```bash
# Enable Tier 1 + 2
bash install_enhancements.sh  # Choose option 2

# Set up Discord alerts
DISCORD_WEBHOOK_URL="https://discord.com/..."

# Let ML learn your patterns for a day
# Then check TUI dashboard daily
```

### Multi-Device Coordination

```bash
# On all devices
DISTRIBUTED_ENABLED=true
CYBERDECK_NETWORK_MODE="peer"
CYBERDECK_PEERS="192.168.1.10,192.168.1.11,192.168.1.12"

# Threats automatically shared
# Consensus blocking across all devices
```

### Research/Learning

```bash
# Enable all tiers
bash install_enhancements.sh  # Choose option 3

# Set up honeypots on high ports
# Review captured credentials
# Analyze packet captures
# Study attack patterns
```

---

## 📈 Performance Impact

| Feature | CPU | RAM | Battery | Network |
|---------|-----|-----|---------|---------|
| Threat Intel | Low | Low | Medium | Medium (API calls) |
| Webhooks | Low | Low | Low | Low |
| Enhanced Honeypots | Medium | Low | Medium | Low |
| TUI Dashboard | Low | Low | None (on-demand) | None |
| Playbooks | Low | Low | Low | None |
| ML Anomaly | Medium | Medium | Medium | None |
| Packet Inspect | High | Medium | High | High (with capture) |
| Distributed | Low | Low | Low | Low |

**Recommendations:**
- On battery: Disable packet inspection
- Low power: Use Tier 1 only
- Performance mode: Enable all tiers

---

## 🔐 Security Considerations

### API Keys
- Store securely in config files (chmod 600)
- Never commit to git
- Rotate periodically
- Use free tier rate limits

### Distributed Mode
- Only on trusted local networks
- Firewall sync port (9999) from internet
- Trust factor prevents false positive amplification
- Consider VPN for multi-site deployments

### Packet Capture
- Requires root (potential risk)
- Captures raw traffic (privacy concern)
- Store captures securely
- Auto-delete old captures

---

## 🚀 Future Roadmap

**Planned Features:**
- Deep learning (neural networks)
- GeoIP visualization
- Email reporting
- Integration with SIEM tools
- Cloud threat feed
- Mobile app companion

**Community Contributions:**
- Custom playbook library
- Signature database
- Threat feed sharing
- Integration modules

---

## 📞 Support

**Issues:**
- Run health check: `bash ~/cyberdeck/healthcheck.sh`
- Check logs: `tail -f ~/cyberdeck/logs/*_output.log`
- Review config: `cat ~/cyberdeck/config/enhancements.conf`

**Questions:**
- Review this guide
- Check main README.md
- Examine playbook examples

---

**🛡️ Enhanced cyberdeck - Maximum protection, maximum intelligence!**
