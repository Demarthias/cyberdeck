# CYBERDECK — Advanced Threat Detection System

A production-ready, daemon-based cybersecurity monitoring system for Linux and Termux environments.

## What it does

Cyberdeck runs as a set of background daemons that continuously monitor your network for threats, score and track hostile IPs, and take automated defensive actions.

- **Real-time network monitoring** — watches all established TCP connections via `ss`/`netstat`
- **Intelligent threat scoring** — adaptive scoring engine with per-IP history
- **Automatic containment** — blocks malicious IPs via iptables, updates in real time
- **Threat intelligence feeds** — integrates with AbuseIPDB, AlienVault OTX, and Tor exit node lists
- **Honeypots** — fake SSH, FTP, HTTP, and WordPress endpoints to catch and fingerprint attackers
- **ML anomaly detection** — statistical baseline analysis to flag unusual behavior
- **Deep packet inspection** — signature-based payload scanning, protocol fingerprinting
- **Automated playbooks** — rule-based response engine (e.g., block after 10 port scan attempts)
- **Live cockpit HUD** — real-time threat status in your terminal prompt
- **Distributed mode** — optional peer network for shared threat intelligence

## Quick Start

```bash
git clone https://github.com/Demarthias/cyberdeck.git
bash cyberdeck/setup.sh
```

Then:

```bash
bash ~/cyberdeck/start.sh
```

## Requirements

- Bash 4.0+
- SQLite3
- `ss` (iproute2) or `netstat`
- `bc`

Optional: root access (iptables blocking), ZSH (cockpit HUD), `tcpdump` (packet capture), `socat`/`nc` (honeypots)

### Termux

```bash
pkg install sqlite iproute2 bc -y
```

## Full Documentation

See [`cyberdeck/README.md`](cyberdeck/README.md) for complete documentation including architecture overview, daemon descriptions, cockpit HUD setup, monitoring queries, and troubleshooting.

## Architecture

```
supervisor.sh          # Orchestrates all daemons
├── sensors/           # Network connection monitoring
├── intelligence/      # Threat scoring engine
├── firewall/          # IP blocking via iptables
├── deception/         # Honeypot services
├── logging/           # Log rotation and archival
├── cockpit/           # Terminal HUD and control interface
└── enhancements/      # Threat intel, ML, DPI, playbooks, webhooks
```

## License

MIT
