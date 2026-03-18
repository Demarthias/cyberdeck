#!/bin/bash
# Cyberdeck Installation Script

set -euo pipefail

echo "═══════════════════════════════════════"
echo "   CYBERDECK INSTALLATION"
echo "═══════════════════════════════════════"
echo ""

# Check if running in Termux
if [ -z "${TERMUX_VERSION:-}" ]; then
    echo "⚠️  Warning: This appears to be a non-Termux environment"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi

# Determine installation directory
INSTALL_DIR="${HOME}/cyberdeck"

if [[ -d "$INSTALL_DIR" ]]; then
    echo "⚠️  Cyberdeck already installed at $INSTALL_DIR"
    read -p "Reinstall? This will preserve logs and config. (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Backup existing data
        BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp -r "${INSTALL_DIR}/logs" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "${INSTALL_DIR}/config" "$BACKUP_DIR/" 2>/dev/null || true
        echo "✅ Backed up to $BACKUP_DIR"
    else
        exit 0
    fi
fi

echo "📦 Installing to: $INSTALL_DIR"
echo ""

# Check for required commands
echo "🔍 Checking dependencies..."

MISSING_DEPS=()

check_dep() {
    if ! command -v "$1" &> /dev/null; then
        MISSING_DEPS+=("$1")
    fi
}

check_dep "bash"
check_dep "sqlite3"
check_dep "ss"
check_dep "bc"

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo "❌ Missing dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "Install with:"
    if command -v pkg &> /dev/null; then
        echo "  pkg install sqlite iproute2 bc -y"
    elif command -v apt &> /dev/null; then
        echo "  apt install sqlite3 iproute2 bc -y"
    fi
    echo ""
    exit 1
fi

echo "✅ All dependencies found"
echo ""

# Copy files
echo "📁 Setting up directory structure..."

mkdir -p "$INSTALL_DIR"
export CYBERDECK_HOME="$INSTALL_DIR"

# Create all directories
mkdir -p "${INSTALL_DIR}"/{firewall,sensors,intelligence,containment,deception,logging,logs,pids,pipes,config,lib,docs,quarantine}

echo "✅ Directories created"
echo ""

# Initialize database
echo "🗄️  Initializing database..."
chmod +x "${INSTALL_DIR}/config/init_db.sh"
bash "${INSTALL_DIR}/config/init_db.sh"

# Make scripts executable
echo "🔧 Setting permissions..."
find "${INSTALL_DIR}" -name "*.sh" -exec chmod +x {} \;
echo "✅ Permissions set"
echo ""

# Initialize pipes
echo "🔗 Creating communication pipes..."
cd "${INSTALL_DIR}/pipes"
for pipe in intel_queue firewall_queue containment_queue cockpit_queue; do
    [[ -p "$pipe" ]] || mkfifo "$pipe"
    chmod 600 "$pipe"
done
echo "✅ Pipes created"
echo ""

# Create control scripts
cat > "${INSTALL_DIR}/start.sh" << 'STARTEOF'
#!/bin/bash
export CYBERDECK_HOME="${HOME}/cyberdeck"
bash "${CYBERDECK_HOME}/supervisor.sh" &
echo "✅ Cyberdeck started"
echo "View status: cd ~/cyberdeck && bash healthcheck.sh"
STARTEOF

cat > "${INSTALL_DIR}/stop.sh" << 'STOPEOF'
#!/bin/bash
export CYBERDECK_HOME="${HOME}/cyberdeck"
for pid_file in "${CYBERDECK_HOME}"/pids/*.pid; do
    [[ -f "$pid_file" ]] || continue
    pid=$(cat "$pid_file")
    kill "$pid" 2>/dev/null && echo "Stopped $(basename "$pid_file" .pid)"
done
echo "✅ Cyberdeck stopped"
STOPEOF

chmod +x "${INSTALL_DIR}/start.sh" "${INSTALL_DIR}/stop.sh"

echo "✅ Control scripts created"
echo ""

# Installation complete
echo "═══════════════════════════════════════"
echo "   INSTALLATION COMPLETE!"
echo "═══════════════════════════════════════"
echo ""
echo "Start cyberdeck:"
echo "  cd ~/cyberdeck && ./start.sh"
echo ""
echo "Stop cyberdeck:"
echo "  cd ~/cyberdeck && ./stop.sh"
echo ""
echo "Check status:"
echo "  cd ~/cyberdeck && bash healthcheck.sh"
echo ""
echo "View logs:"
echo "  tail -f ~/cyberdeck/logs/*.log"
echo ""
echo "Edit configuration:"
echo "  nano ~/cyberdeck/config/cyberdeck.conf"
echo ""

exit 0
