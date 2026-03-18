#!/bin/bash
# Validation script - checks installation without running

echo "═══════════════════════════════════════"
echo "   CYBERDECK VALIDATION"
echo "═══════════════════════════════════════"
echo ""

CYBERDECK_HOME="${CYBERDECK_HOME:-$HOME/cyberdeck}"
ERRORS=0

check_file() {
    if [[ -f "$1" ]]; then
        echo "  ✅ $1"
    else
        echo "  ❌ MISSING: $1"
        ((ERRORS++))
    fi
}

check_dir() {
    if [[ -d "$1" ]]; then
        echo "  ✅ $1"
    else
        echo "  ❌ MISSING: $1"
        ((ERRORS++))
    fi
}

check_executable() {
    if [[ -x "$1" ]]; then
        echo "  ✅ $1 (executable)"
    else
        echo "  ❌ $1 (not executable)"
        ((ERRORS++))
    fi
}

echo "📁 Directory Structure:"
for dir in firewall sensors intelligence containment deception logging logs pids pipes config lib docs quarantine; do
    check_dir "${CYBERDECK_HOME}/$dir"
done

echo ""
echo "📄 Core Files:"
check_file "${CYBERDECK_HOME}/README.md"
check_file "${CYBERDECK_HOME}/QUICKSTART.md"
check_file "${CYBERDECK_HOME}/config/cyberdeck.conf"
check_file "${CYBERDECK_HOME}/lib/common.sh"

echo ""
echo "🔧 Executable Scripts:"
check_executable "${CYBERDECK_HOME}/install.sh"
check_executable "${CYBERDECK_HOME}/supervisor.sh"
check_executable "${CYBERDECK_HOME}/healthcheck.sh"
check_executable "${CYBERDECK_HOME}/config/init_db.sh"

echo ""
echo "👾 Daemons:"
check_executable "${CYBERDECK_HOME}/sensors/sensor.sh"
check_executable "${CYBERDECK_HOME}/intelligence/intel.sh"
check_executable "${CYBERDECK_HOME}/firewall/firewall.sh"
check_executable "${CYBERDECK_HOME}/containment/containment.sh"
check_executable "${CYBERDECK_HOME}/logging/logging.sh"

echo ""
echo "🎨 Cockpit:"
check_file "${CYBERDECK_HOME}/cockpit/cockpit.zsh"

echo ""
echo "═══════════════════════════════════════"

if [[ $ERRORS -eq 0 ]]; then
    echo "  ✅ All files present and valid!"
    echo "  Ready to install on target system"
else
    echo "  ❌ Found $ERRORS error(s)"
    echo "  Please check missing files"
fi

echo "═══════════════════════════════════════"
echo ""

exit $ERRORS
