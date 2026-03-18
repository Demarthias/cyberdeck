#!/bin/bash
# Initialize SQLite database for threat tracking

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CYBERDECK_HOME="$(dirname "$SCRIPT_DIR")"
export CYBERDECK_HOME

source "${CYBERDECK_HOME}/lib/common.sh"

DB_PATH=$(get_db_path)

echo "Initializing database at: $DB_PATH"

# Create database and tables
sqlite3 "$DB_PATH" <<'EOF' || { echo "Database initialization failed" >&2; exit 1; }
-- Threat tracking table
CREATE TABLE IF NOT EXISTS threats (
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

-- Index for faster queries
CREATE INDEX IF NOT EXISTS idx_threats_score ON threats(total_score);
CREATE INDEX IF NOT EXISTS idx_threats_blocked ON threats(blocked);
CREATE INDEX IF NOT EXISTS idx_threats_last_seen ON threats(last_seen);

-- Connection history table
CREATE TABLE IF NOT EXISTS connections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    ip TEXT NOT NULL,
    port INTEGER,
    protocol TEXT,
    state TEXT,
    process_name TEXT
);

-- Index for connection queries
CREATE INDEX IF NOT EXISTS idx_connections_ip ON connections(ip);
CREATE INDEX IF NOT EXISTS idx_connections_timestamp ON connections(timestamp);

-- Alert history table
CREATE TABLE IF NOT EXISTS alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    alert_type TEXT NOT NULL,
    ip TEXT,
    score INTEGER,
    message TEXT,
    acknowledged INTEGER DEFAULT 0
);

-- Index for alert queries
CREATE INDEX IF NOT EXISTS idx_alerts_timestamp ON alerts(timestamp);
CREATE INDEX IF NOT EXISTS idx_alerts_type ON alerts(alert_type);

-- Action log table
CREATE TABLE IF NOT EXISTS actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    action_type TEXT NOT NULL,
    ip TEXT,
    daemon TEXT NOT NULL,
    details TEXT,
    success INTEGER DEFAULT 1
);

-- Index for action queries
CREATE INDEX IF NOT EXISTS idx_actions_timestamp ON actions(timestamp);
CREATE INDEX IF NOT EXISTS idx_actions_type ON actions(action_type);
CREATE INDEX IF NOT EXISTS idx_actions_ip ON actions(ip);

-- System stats table
CREATE TABLE IF NOT EXISTS stats (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated INTEGER
);

-- Insert initial stats
INSERT OR IGNORE INTO stats (key, value, updated) VALUES 
    ('total_threats_blocked', '0', strftime('%s', 'now')),
    ('total_connections_monitored', '0', strftime('%s', 'now')),
    ('total_alerts_generated', '0', strftime('%s', 'now')),
    ('system_start_time', strftime('%s', 'now'), strftime('%s', 'now'));

EOF

if [[ $? -eq 0 ]]; then
    echo "✅ Database initialized successfully"
    chmod 600 "$DB_PATH"
    echo "✅ Permissions set to 600"
else
    echo "❌ Database initialization failed"
    exit 1
fi

# Create initial backup
BACKUP_DIR="${CYBERDECK_HOME}/config/backups"
mkdir -p "$BACKUP_DIR"
cp "$DB_PATH" "${BACKUP_DIR}/threats_$(date +%Y%m%d_%H%M%S).db"
echo "✅ Initial backup created"

exit 0
