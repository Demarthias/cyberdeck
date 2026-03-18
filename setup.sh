#!/bin/bash
# Cyberdeck setup — run this once after cloning
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/cyberdeck"
TARBALL="${REPO_DIR}/cyberdeck/cyberdeck-production.tar.gz"

echo "=== CYBERDECK SETUP ==="
echo ""

# --- Dependencies ---
echo "Checking dependencies..."
MISSING=()
for cmd in bash sqlite3 bc; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
# ss or netstat
if ! command -v ss &>/dev/null && ! command -v netstat &>/dev/null; then
    MISSING+=("ss (iproute2)")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "Missing: ${MISSING[*]}"
    echo ""
    if command -v pkg &>/dev/null; then
        echo "Run: pkg install sqlite iproute2 bc -y"
    elif command -v apt &>/dev/null; then
        echo "Run: sudo apt install sqlite3 iproute2 bc -y"
    fi
    exit 1
fi
echo "Dependencies OK"
echo ""

# --- Extract ---
if [[ ! -f "$TARBALL" ]]; then
    echo "ERROR: tarball not found at $TARBALL"
    exit 1
fi

if [[ -d "$INSTALL_DIR" ]]; then
    echo "WARNING: $INSTALL_DIR already exists. Removing and reinstalling..."
    rm -rf "$INSTALL_DIR"
fi

echo "Extracting to $INSTALL_DIR ..."
tar -xzf "$TARBALL" -C "$HOME"
echo "Extracted"
echo ""

# --- Permissions ---
echo "Setting permissions..."
find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
echo "Done"
echo ""

# --- Database ---
echo "Initializing database..."
export CYBERDECK_HOME="$INSTALL_DIR"
bash "${INSTALL_DIR}/config/init_db.sh"
echo "Database ready"
echo ""

# --- Pipes ---
echo "Creating pipes..."
mkdir -p "${INSTALL_DIR}/pipes"
for pipe in intel_queue firewall_queue containment_queue cockpit_queue; do
    [[ -p "${INSTALL_DIR}/pipes/$pipe" ]] || mkfifo "${INSTALL_DIR}/pipes/$pipe"
    chmod 600 "${INSTALL_DIR}/pipes/$pipe"
done
echo "Pipes ready"
echo ""

# --- Control scripts ---
cat > "${INSTALL_DIR}/start.sh" <<'EOF'
#!/bin/bash
export CYBERDECK_HOME="${HOME}/cyberdeck"
bash "${CYBERDECK_HOME}/supervisor.sh" &
echo "Cyberdeck started. Run: bash ~/cyberdeck/healthcheck.sh"
EOF

cat > "${INSTALL_DIR}/stop.sh" <<'EOF'
#!/bin/bash
export CYBERDECK_HOME="${HOME}/cyberdeck"
for pid_file in "${CYBERDECK_HOME}"/pids/*.pid; do
    [[ -f "$pid_file" ]] || continue
    pid=$(cat "$pid_file")
    kill "$pid" 2>/dev/null && echo "Stopped $(basename "$pid_file" .pid)"
done
echo "Cyberdeck stopped"
EOF

chmod +x "${INSTALL_DIR}/start.sh" "${INSTALL_DIR}/stop.sh"

echo "=== DONE ==="
echo ""
echo "  Start:   bash ~/cyberdeck/start.sh"
echo "  Stop:    bash ~/cyberdeck/stop.sh"
echo "  Status:  bash ~/cyberdeck/healthcheck.sh"
echo "  Logs:    tail -f ~/cyberdeck/logs/*.log"
echo ""
