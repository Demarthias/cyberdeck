# ⚡ CYBERDECK QUICK START

## 5-Minute Setup

### 1. Install Dependencies
```bash
# Termux
pkg install sqlite iproute2 bc -y

# Debian/Ubuntu
apt install sqlite3 iproute2 bc -y
```

### 2. Run Installer
```bash
cd ~/cyberdeck
chmod +x install.sh
./install.sh
```

### 3. Start System
```bash
cd ~/cyberdeck
./start.sh
```

### 4. Verify Running
```bash
bash healthcheck.sh
```

## 🎯 Essential Commands

```bash
# Start
./start.sh

# Stop  
./stop.sh

# Status check
bash healthcheck.sh

# View live logs
tail -f logs/*.log

# View alerts
tail -f logs/cockpit_alerts.txt

# View top threats
sqlite3 config/threats.db "SELECT ip, total_score, blocked FROM threats ORDER BY total_score DESC LIMIT 5;"
```

## 🎛️ Customize Before Starting

Edit `config/cyberdeck.conf`:

```bash
# Make it more sensitive (detect more threats)
THREAT_THRESHOLD_NOTIFY=3
THREAT_THRESHOLD_BLOCK=6

# Make it less sensitive (fewer false positives)
THREAT_THRESHOLD_NOTIFY=7
THREAT_THRESHOLD_BLOCK=10

# Add trusted IP
TRUSTED_IPS=("127.0.0.1" "192.168.1.100" "192.168.1.200")
```

## 🚨 Troubleshooting

**Nothing detected?**
```bash
# Lower thresholds
nano config/cyberdeck.conf
# Set THREAT_THRESHOLD_NOTIFY=1

# Restart
./stop.sh && ./start.sh
```

**Daemon crashed?**
```bash
# Check logs
cat logs/sensor.out
cat logs/intel.out

# Supervisor will auto-restart
# Or manually restart
./stop.sh && ./start.sh
```

**Database locked?**
```bash
# Kill processes using it
fuser -k config/threats.db

# Restart
./stop.sh && ./start.sh
```

## 🎨 Add to ZSH Prompt

```bash
# Add to ~/.zshrc
source ~/cyberdeck/cockpit/cockpit.zsh
PROMPT='$(cyberdeck_prompt) %n@%m %~ %# '

# Reload
source ~/.zshrc
```

Now your prompt will show:
- `✓` = Green (safe)
- `⚡` = Yellow (suspicious activity)
- `⚠` = Red (threat blocked)

## 📊 View Dashboard

Full-screen HUD:
```bash
source ~/cyberdeck/cockpit/cockpit.zsh
cyberdeck_hud
```

Press `Ctrl+C` to exit.

---

**That's it! You now have a professional-grade threat detection system running.**
