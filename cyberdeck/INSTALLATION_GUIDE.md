# 🛡️ CYBERDECK - COMPLETE INSTALLATION GUIDE

## 📦 DOWNLOAD PACKAGE

**File:** `cyberdeck-complete-with-enhancements.tar.gz` (51KB)

**Contains:**
- Complete base cyberdeck system (7 daemons)
- All Tier 1-3 enhancements (8 modules)  
- Configuration files
- Installation scripts
- Full documentation

---

## 🚀 INSTALLATION (5 MINUTES)

### Step 1: Transfer to Termux

```bash
# Download the .tar.gz file to your device
# Open Termux and navigate to download location
cd ~/storage/downloads  # or wherever you saved it

# Move to home directory
mv cyberdeck-complete-with-enhancements.tar.gz ~/
cd ~
```

### Step 2: Extract

```bash
tar -xzf cyberdeck-complete-with-enhancements.tar.gz
cd cyberdeck
```

### Step 3: Install Dependencies

```bash
# Essential (required)
pkg update
pkg install sqlite iproute2 netcat-openbsd -y

# Optional (for full features)
pkg install dialog socat tcpdump bc curl -y
```

### Step 4: Install Base System

```bash
bash install.sh
```

**You'll be asked:**
- ✓ Checks dependencies
- ✓ Creates directories
- ✓ Initializes database
- ✓ Sets up shell integration
- ✓ "Start cyberdeck now?" → Type `y`

### Step 5: Install Enhancements

```bash
bash install_enhancements.sh
```

**Choose your tier:**
- `1` = Tier 1 only (Threat Intel + Webhooks)
- `2` = Tiers 1+2 (+ Honeypots + TUI + Playbooks) **← RECOMMENDED**
- `3` = All tiers (+ ML + DPI + Distributed)

### Step 6: Configure API Keys (Optional but Recommended)

```bash
nano ~/cyberdeck/config/enhancements.conf
```

**Add these (all free):**
```bash
# Get from: https://www.abuseipdb.com/api
ABUSEIPDB_API_KEY="your_key_here"

# Get from: https://otx.alienvault.com/
OTX_API_KEY="your_key_here"

# Get from Discord server settings
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."
```

**Save:** `Ctrl+X`, then `Y`, then `Enter`

### Step 7: Start Everything

```bash
bash ~/cyberdeck/start_enhanced.sh
```

### Step 8: Verify It's Working

```bash
# Reload shell
source ~/.zshrc  # or source ~/.bashrc

# Check status
cyberdeck status
```

**You should see:**
```
=== CYBERDECK STATUS ===
[VENOM] ● SECURE | Daemons: 5/5 | Threats: 0 | Blocked: 0
```

---

## 🎮 BASIC COMMANDS

```bash
cyberdeck status       # View system status
cyberdeck threats      # View top threats
cyberdeck logs         # View daemon logs
cyberdeck block IP     # Manually block IP
cyberdeck help         # Show all commands
```

---

## 🖥️ LAUNCH TUI DASHBOARD

```bash
bash ~/cyberdeck/enhancements/tui_dashboard.sh
```

**Interactive menu lets you:**
- View system status
- Browse top threats
- See recent alerts
- View logs
- Block/unblock IPs
- Manage daemons
- View statistics

**Navigate:** Arrow keys + Enter  
**Exit:** Press `0`

---

## 📊 WHAT EACH TIER GIVES YOU

### **BASE SYSTEM** (Always Included)
- Network monitoring
- Threat scoring algorithm
- IP blocking (iptables or app-layer)
- Basic honeypots
- SQLite database
- Log management
- Self-healing supervisor

### **TIER 1** (Essential)
- ✅ AbuseIPDB (1000 abuse reports/day)
- ✅ AlienVault OTX (threat intelligence)
- ✅ Tor exit node detection
- ✅ Discord alerts
- ✅ Slack alerts

### **TIER 2** (Recommended)
- ✅ Everything from Tier 1
- ✅ Cowrie-style SSH honeypot
- ✅ Fake WordPress (captures credentials)
- ✅ Fake MySQL & RDP
- ✅ TUI Dashboard (interactive interface)
- ✅ Automated Playbooks (if X then Y)

### **TIER 3** (Maximum Power)
- ✅ Everything from Tier 1+2
- ✅ Machine Learning anomaly detection
- ✅ Deep packet inspection
- ✅ Exploit signature matching
- ✅ Distributed network (multi-device)

---

## 💡 QUICK EXAMPLES

### Monitor Live Threats

```bash
# Watch sensor detect connections
tail -f ~/cyberdeck/logs/sensor.log

# Watch alerts as they happen
tail -f ~/cyberdeck/logs/alerts.log

# Watch honeypot captures
tail -f ~/cyberdeck/logs/honeypots/*.log
```

### View Threat Database

```bash
sqlite3 ~/cyberdeck/cyberdeck.db

# In SQLite:
SELECT ip, total_score, blocked FROM threats ORDER BY total_score DESC LIMIT 10;
.quit
```

### Check What's Blocked

```bash
cyberdeck threats

# Or directly:
cat ~/cyberdeck/config/blocked_ips.txt
```

### Create Custom Automation

```bash
# Edit playbook rules
nano ~/cyberdeck/playbooks/rules.conf

# Add rules like:
# port_scan|ports_gt_10|block_ip|
# wordpress_hit|always|increase_score|5
# tor_exit|always|tag|tor_user
```

---

## 🔍 MONITORING & LOGS

### Important Log Files

```bash
~/cyberdeck/logs/
  sensor.log              # Network activity
  intel.log               # Decision making
  firewall.log            # Blocking actions
  alerts.log              # All alerts
  threat_intel_output.log # API results
  webhook_output.log      # Alert deliveries
  honeypots/              # Captured attacks
```

### Real-Time Monitoring

```bash
# Watch all activity
tail -f ~/cyberdeck/logs/*.log

# Watch specific daemon
cyberdeck logs sensor

# Search for IP
grep "203.0.113.42" ~/cyberdeck/logs/*.log
```

---

## 🎯 USE CASES

### 1. Personal Phone Protection

```bash
# Install Tier 1+2
# Enable Discord alerts
# Check TUI dashboard daily
# Let honeypots catch attackers
```

### 2. Home Network Defense

```bash
# Install on old Android phone
# Connect to WiFi
# Enable all tiers
# Place near router
# Monitors entire network
```

### 3. Security Research

```bash
# Install Tier 3
# Enable packet capture
# Review honeypot logs
# Analyze attack patterns
# Study exploit signatures
```

---

## 🔧 TROUBLESHOOTING

### Problem: "No threats detected"

```bash
# Check if connections are being monitored
ss -tn | grep ESTAB

# Verify database has connections
sqlite3 ~/cyberdeck/cyberdeck.db "SELECT COUNT(*) FROM connections;"

# If count is 0, check sensor daemon
tail ~/cyberdeck/logs/sensor.log
```

### Problem: "Daemons not running"

```bash
# Run health check
bash ~/cyberdeck/healthcheck.sh

# Restart everything
bash ~/cyberdeck/stop.sh
sleep 2
bash ~/cyberdeck/start_enhanced.sh
```

### Problem: "TUI won't start"

```bash
# Install dialog
pkg install dialog -y

# Try again
bash ~/cyberdeck/enhancements/tui_dashboard.sh
```

---

## 📱 GET API KEYS (FREE)

### AbuseIPDB (1-2 minutes)
1. Go to: https://www.abuseipdb.com/register
2. Verify email
3. Account → API → Create Key
4. Copy key
5. Free: 1,000 checks/day

### AlienVault OTX (1-2 minutes)
1. Go to: https://otx.alienvault.com/
2. Create account
3. Settings → API Integration
4. Copy key
5. Free: Unlimited

### Discord Webhook (30 seconds)
1. Open Discord server
2. Settings → Integrations → Webhooks
3. New Webhook
4. Copy URL
5. Free: Unlimited

---

## 🎓 LEARNING PATH

### Week 1: Learn the Basics
- Install base system
- Learn commands (`cyberdeck status`, `cyberdeck threats`)
- Watch logs to understand activity
- Try blocking/unblocking IPs manually

### Week 2: Add Intelligence
- Get AbuseIPDB key
- Enable Tier 1
- Watch threat scores boost
- Set up Discord alerts

### Week 3: Advanced Features
- Enable Tier 2
- Launch TUI dashboard
- Create custom playbook rules
- Monitor honeypots

### Week 4: Master Level
- Enable Tier 3 if interested
- Review ML baselines
- Analyze packet captures
- Share between devices

---

## 📚 DOCUMENTATION

All documentation is in the package:

- **README.md** - Complete system guide
- **QUICKSTART.md** - 5-minute quick start
- **ENHANCEMENTS.md** - Enhancement guide
- **IMPROVEMENTS_SUMMARY.md** - Technical details

Read these in order:
```bash
cat ~/cyberdeck/QUICKSTART.md | less
cat ~/cyberdeck/README.md | less
cat ~/cyberdeck/ENHANCEMENTS.md | less
```

---

## 🏁 YOU'RE DONE!

**Your device now has:**
- ✅ Real-time threat detection
- ✅ Global threat intelligence
- ✅ Automatic IP blocking
- ✅ Honeypots capturing attacks
- ✅ Machine learning (if Tier 3)
- ✅ Discord/Slack alerts
- ✅ Interactive dashboard
- ✅ Automated responses

**Next Steps:**
1. ⚡ Let it run for 24 hours to build baselines
2. 📱 Check Discord for alerts
3. 🎮 Explore TUI dashboard daily
4. 📊 Review weekly threat summaries

**Daily Routine:**
```bash
# Morning check (30 seconds)
bash ~/cyberdeck/enhancements/tui_dashboard.sh
# → View Status → View Threats → Exit
```

**🛡️ Welcome to enterprise-grade mobile cybersecurity!**
