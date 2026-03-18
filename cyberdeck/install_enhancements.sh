#!/bin/bash
# Cyberdeck Enhancements Installation Script
# Installs Tier 1-3 advanced features

set -e

echo "========================================"
echo "  CYBERDECK ENHANCEMENTS INSTALLATION"
echo "========================================"
echo ""

CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"

# Check if base cyberdeck is installed
if [[ ! -d "$CYBERDECK_HOME" ]]; then
    echo "ERROR: Base cyberdeck not found at $CYBERDECK_HOME"
    echo "Please install the base cyberdeck first."
    exit 1
fi

# === Check Dependencies ===

echo "[1/5] Checking dependencies..."

MISSING_DEPS=()

# Core dependencies
for cmd in sqlite3 curl bc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_DEPS+=($cmd)
    fi
done

# Optional dependencies
OPTIONAL_MISSING=()

if ! command -v dialog >/dev/null 2>&1 && ! command -v whiptail >/dev/null 2>&1; then
    OPTIONAL_MISSING+=("dialog or whiptail (for TUI dashboard)")
fi

if ! command -v socat >/dev/null 2>&1; then
    OPTIONAL_MISSING+=("socat (for enhanced honeypots)")
fi

if ! command -v tcpdump >/dev/null 2>&1; then
    OPTIONAL_MISSING+=("tcpdump (for packet inspection)")
fi

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo "ERROR: Missing required dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "To install in Termux, run:"
    echo "  pkg install sqlite curl bc -y"
    echo ""
    exit 1
fi

echo "✓ Required dependencies satisfied"

if [[ ${#OPTIONAL_MISSING[@]} -gt 0 ]]; then
    echo "⚠ Optional dependencies missing:"
    for dep in "${OPTIONAL_MISSING[@]}"; do
        echo "    - $dep"
    done
    echo ""
    echo "To install optional features in Termux:"
    echo "  pkg install dialog socat tcpdump -y"
    echo ""
    read -p "Continue without optional dependencies? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# === Create Directories ===

echo "[2/5] Creating enhancement directories..."

mkdir -p "$CYBERDECK_HOME"/{enhancements,cache/ml,playbooks,pcaps}

echo "✓ Directories created"

# === Copy Enhancement Files ===

echo "[3/5] Installing enhancement modules..."

ENHANCEMENTS_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/enhancements"

if [[ -d "$ENHANCEMENTS_SOURCE" ]]; then
    cp -f "$ENHANCEMENTS_SOURCE"/*.sh "$CYBERDECK_HOME/enhancements/" 2>/dev/null || true
    chmod +x "$CYBERDECK_HOME/enhancements"/*.sh
fi

# Copy configuration
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/config/enhancements.conf" ]]; then
    cp -f "$(dirname "${BASH_SOURCE[0]}")/config/enhancements.conf" "$CYBERDECK_HOME/config/"
fi

echo "✓ Enhancement modules installed"

# === Update Configuration ===

echo "[4/5] Updating configuration..."

# Source enhancements config in main config
if ! grep -q "enhancements.conf" "$CYBERDECK_HOME/config/cyberdeck.conf" 2>/dev/null; then
    echo "" >> "$CYBERDECK_HOME/config/cyberdeck.conf"
    echo "# Load enhancements configuration" >> "$CYBERDECK_HOME/config/cyberdeck.conf"
    echo "[[ -f \"\${CYBERDECK_HOME}/config/enhancements.conf\" ]] && source \"\${CYBERDECK_HOME}/config/enhancements.conf\"" >> "$CYBERDECK_HOME/config/cyberdeck.conf"
fi

echo "✓ Configuration updated"

# === Feature Selection ===

echo "[5/5] Configuring features..."

cat <<EOF

Which enhancement tiers would you like to enable?

TIER 1 (Essential):
  ✓ Threat Intelligence (AbuseIPDB, Tor, OTX)
  ✓ Webhook Alerts (Discord, Slack)

TIER 2 (Advanced):
  ✓ Enhanced Honeypots (SSH, WordPress, MySQL)
  ✓ TUI Dashboard (Interactive terminal interface)
  ✓ Automated Playbooks (Rule-based responses)

TIER 3 (Experimental):
  ✓ Machine Learning Anomaly Detection
  ✓ Packet Inspection & DPI
  ✓ Distributed Network Coordination

EOF

# Simple tier selection
echo "Select tiers to enable:"
echo "  1) Tier 1 only"
echo "  2) Tiers 1 + 2"
echo "  3) All tiers (1 + 2 + 3)"
echo ""
read -p "Choice (1-3): " tier_choice

ENABLE_TIER1=false
ENABLE_TIER2=false
ENABLE_TIER3=false

case $tier_choice in
    1) ENABLE_TIER1=true ;;
    2) ENABLE_TIER1=true; ENABLE_TIER2=true ;;
    3) ENABLE_TIER1=true; ENABLE_TIER2=true; ENABLE_TIER3=true ;;
    *) ENABLE_TIER1=true ;;  # Default to tier 1
esac

# Update enhancements config
cat > "$CYBERDECK_HOME/config/enhancements.conf" <<EOF
# Cyberdeck Enhancements Configuration
# Auto-generated on $(date)

# === TIER 1 Features ===
TIER1_ENABLED=$ENABLE_TIER1
WEBHOOK_ENABLED=$ENABLE_TIER1

# === TIER 2 Features ===
TIER2_ENABLED=$ENABLE_TIER2
ENHANCED_HONEYPOTS_ENABLED=$ENABLE_TIER2
PLAYBOOKS_ENABLED=$ENABLE_TIER2

# === TIER 3 Features ===
TIER3_ENABLED=$ENABLE_TIER3
ML_ANOMALY_ENABLED=$ENABLE_TIER3
PACKET_INSPECTION_ENABLED=$ENABLE_TIER3
DISTRIBUTED_ENABLED=false  # Manual configuration required

# === API Keys (configure these manually) ===
ABUSEIPDB_API_KEY=""
OTX_API_KEY=""
DISCORD_WEBHOOK_URL=""
SLACK_WEBHOOK_URL=""

# === See full configuration in: ===
# $CYBERDECK_HOME/config/enhancements.conf
EOF

echo "✓ Features configured"

# === Create Enhanced Supervisor ===

echo ""
echo "Creating enhanced supervisor script..."

cat > "$CYBERDECK_HOME/start_enhanced.sh" <<'EOFSCRIPT'
#!/bin/bash
# Start cyberdeck with enhancements

CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"
source "$CYBERDECK_HOME/config/cyberdeck.conf"
source "$CYBERDECK_HOME/config/enhancements.conf" 2>/dev/null || true

# Start base daemons
bash "$CYBERDECK_HOME/supervisor.sh" &

# Wait for base system to initialize
sleep 3

# Start enhancement daemons based on tier
if [[ "$TIER1_ENABLED" == "true" ]]; then
    echo "Starting Tier 1 enhancements..."
    nohup bash "$CYBERDECK_HOME/enhancements/threat_intel.sh" >> "$CYBERDECK_HOME/logs/threat_intel_output.log" 2>&1 &
    nohup bash "$CYBERDECK_HOME/enhancements/webhook_alerts.sh" >> "$CYBERDECK_HOME/logs/webhook_output.log" 2>&1 &
fi

if [[ "$TIER2_ENABLED" == "true" ]]; then
    echo "Starting Tier 2 enhancements..."
    [[ "$ENHANCED_HONEYPOTS_ENABLED" == "true" ]] && nohup bash "$CYBERDECK_HOME/enhancements/enhanced_honeypots.sh" >> "$CYBERDECK_HOME/logs/honeypots_output.log" 2>&1 &
    [[ "$PLAYBOOKS_ENABLED" == "true" ]] && nohup bash "$CYBERDECK_HOME/enhancements/playbooks.sh" >> "$CYBERDECK_HOME/logs/playbooks_output.log" 2>&1 &
fi

if [[ "$TIER3_ENABLED" == "true" ]]; then
    echo "Starting Tier 3 enhancements..."
    [[ "$ML_ANOMALY_ENABLED" == "true" ]] && nohup bash "$CYBERDECK_HOME/enhancements/ml_anomaly.sh" >> "$CYBERDECK_HOME/logs/ml_output.log" 2>&1 &
    [[ "$PACKET_INSPECTION_ENABLED" == "true" ]] && nohup bash "$CYBERDECK_HOME/enhancements/packet_inspect.sh" >> "$CYBERDECK_HOME/logs/packet_output.log" 2>&1 &
    [[ "$DISTRIBUTED_ENABLED" == "true" ]] && nohup bash "$CYBERDECK_HOME/enhancements/distributed.sh" >> "$CYBERDECK_HOME/logs/distributed_output.log" 2>&1 &
fi

echo "Cyberdeck enhancements started!"
EOFSCRIPT

chmod +x "$CYBERDECK_HOME/start_enhanced.sh"

# === Installation Complete ===

echo ""
echo "========================================"
echo "  INSTALLATION COMPLETE"
echo "========================================"
echo ""
echo "Enhancements installed to: $CYBERDECK_HOME/enhancements/"
echo ""
echo "Enabled features:"
[[ "$ENABLE_TIER1" == "true" ]] && echo "  ✓ Tier 1: Threat Intelligence + Webhooks"
[[ "$ENABLE_TIER2" == "true" ]] && echo "  ✓ Tier 2: Enhanced Honeypots + TUI + Playbooks"
[[ "$ENABLE_TIER3" == "true" ]] && echo "  ✓ Tier 3: ML + Packet Inspection + Distributed"
echo ""
echo "Next steps:"
echo "  1. Configure API keys (optional):"
echo "     nano $CYBERDECK_HOME/config/enhancements.conf"
echo ""
echo "  2. Start with enhancements:"
echo "     bash $CYBERDECK_HOME/start_enhanced.sh"
echo ""
echo "  3. Launch TUI dashboard:"
echo "     bash $CYBERDECK_HOME/enhancements/tui_dashboard.sh"
echo ""
echo "  4. View enhancement logs:"
echo "     tail -f $CYBERDECK_HOME/logs/*_output.log"
echo ""
echo "🛡️  Your cyberdeck is now supercharged!"
