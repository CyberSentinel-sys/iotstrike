```
  ___   ___  _____  ___  _            _  _
 |_ _| / _ \|_   _|/ __|| |_  _ _  (_)| |__ ___
  | | | (_) | | |  \__ \|  _|| '_| | || / // -_)
 |___| \___/  |_|  |___/ \__||_|   |_||_\_\\__|

  Universal IoT Security Framework
  Emulate · Scan · CVE Intel · Sessions · Web UI · Reports
```

> **Author:** Yechiel Said ([@CyberSentinel-sys](https://github.com/CyberSentinel-sys))
> **Contact:** yechielstudy@gmail.com
> **Issues:** https://github.com/CyberSentinel-sys/iotstrike/issues

---

## ⚠️ Legal Disclaimer

**IoTStrike is intended exclusively for authorized security research, educational purposes, and professional penetration testing engagements where explicit written permission has been obtained from the device/network owner.**

- Do **NOT** use this tool against any device, network, or system you do not own or do not have explicit, written authorization to test.
- Unauthorized use may violate the Computer Fraud and Abuse Act (CFAA), the UK Computer Misuse Act, the EU Directive on Attacks Against Information Systems, and equivalent laws in your jurisdiction.
- **The author (Yechiel Said / CyberSentinel-sys) accepts no liability whatsoever for any damage, legal consequences, or misuse arising from the use or misuse of this software.**
- This tool is provided **AS IS**, with no warranty of any kind, express or implied.

By downloading, installing, or running IoTStrike you agree to these terms.

---

## Features

| Module | Description | Tools |
|--------|-------------|-------|
| **Firmware Emulation** | Extract and emulate MIPS/ARM IoT firmware in QEMU | Firmadyne, FirmAE, EMBA |
| **Scan & Attack** | Port scanning, web vulnerability scanning, default credential testing | nmap, nikto, hydra, Metasploit |
| **CVE Intelligence** | Real-time CVE lookups from the NIST NVD API; CVSS severity filtering | NVD REST API v2 |
| **Session Manager** | Save, restore, and compare pentest sessions across reboots | bash env files |
| **Web Dashboard** | Live status dashboard at `localhost:8080` showing target IP, ports, CVEs, and scan logs | Flask, auto-refresh JS |
| **Report Generator** | Export professional Markdown and HTML assessment reports | Python + bash |

---

## Requirements

- **OS:** Kali Linux 2023–2026 (amd64) — other Debian-based systems may work
- **Privileges:** Root (`sudo`) required for QEMU, network configuration, and package installation
- **Internet access:** Required during setup (apt, GitHub clones, NVD API queries)
- **Disk space:** ~4 GB recommended (QEMU kernels, firmware images, Firmadyne)

---

## Installation

```bash
# Clone or download the repository, then run the setup script once:
sudo bash Iotstrike.sh
```

The setup script will:
1. Update and upgrade all system packages
2. Install all required tools (`nmap`, `nikto`, `hydra`, `qemu-*`, `postgresql`, `binwalk`, etc.)
3. Clone and configure [Firmadyne](https://github.com/firmadyne/firmadyne)
4. Clone [Binwalk](https://github.com/ReFirmLabs/binwalk) and install its dependencies
5. Set up a PostgreSQL database for Firmadyne
6. Download MIPS/ARM QEMU kernels
7. Create the IoTStrike directory structure at `/opt/iotstrike/`
8. Write the runner script to `/opt/iotstrike/IoTStrike.sh`

---

## Usage

### Interactive Menu

```bash
sudo bash /opt/iotstrike/IoTStrike.sh
```

On startup you will be prompted to select a firmware file. Background CVE lookups and (if EMBA is installed) static analysis begin immediately while you navigate the menu.

```
  [1] Emulate firmware     Firmadyne · FirmAE · EMBA
  [2] Scan & attack        nmap · nikto · hydra · metasploit
  [3] CVE intelligence     NVD API · auto-lookup · CVSS alerts
  [4] Session manager      save · restore · compare targets
  [5] Web dashboard        live status at localhost:8080
  [6] Report generator     HTML + markdown export
  [0] Exit
```

### CLI Flags (Non-Interactive)

```bash
# Emulate a firmware image via Firmadyne
sudo bash /opt/iotstrike/IoTStrike.sh --emulate /path/to/firmware.zip

# Run the full scan pipeline (nmap + nikto + hydra) against a target
sudo bash /opt/iotstrike/IoTStrike.sh --scan 192.168.0.100

# Fetch CVE data for a vendor from the NVD API
sudo bash /opt/iotstrike/IoTStrike.sh --cve netgear
sudo bash /opt/iotstrike/IoTStrike.sh --cve tplink

# Generate a report from the current session
sudo bash /opt/iotstrike/IoTStrike.sh --report html
sudo bash /opt/iotstrike/IoTStrike.sh --report md

# Start the web API server (default port 8080, localhost only)
sudo bash /opt/iotstrike/IoTStrike.sh --web 8080
```

### Web API Server

```bash
# Start the Flask API server (prints a one-time API key on startup)
sudo python3 /opt/iotstrike/iot_web_server.py

# Optional: bind to a custom port
sudo python3 /opt/iotstrike/iot_web_server.py --port 9090
```

> **Security note:** The web server binds to `127.0.0.1` (localhost only) by default.
> All `/api/*` endpoints require authentication via a randomly generated key
> that is printed to the console at startup.

**API authentication:**
```bash
# Use the key printed at startup
API_KEY="<key printed at startup>"

# Bearer token header
curl -H "Authorization: Bearer $API_KEY" http://127.0.0.1:8080/api/status

# Or query parameter
curl "http://127.0.0.1:8080/api/status?api_key=$API_KEY"
```

**API endpoints:**
```
GET  /                        Web dashboard (no auth required)
GET  /status.json             Live status JSON (no auth required)
POST /api/upload              Upload firmware → trigger --emulate
POST /api/command             Trigger --scan or --cve
GET  /api/status              Current session status (auth required)
GET  /api/logs/<filename>     Last 100 lines of a log file (auth required)
```

---

## Directory Structure (after setup)

```
/opt/iotstrike/
├── IoTStrike.sh          Runner script (generated by setup)
├── iot_web_server.py     Flask web API server
├── firmadyne/            Firmadyne clone + QEMU kernels
├── binwalk/              Binwalk clone
├── tools/                Python virtual environment
├── web/                  Dashboard HTML + status.json
├── uploads/              Uploaded firmware files
├── logs/                 Scan and CVE logs
├── sessions/             Saved session files
├── reports/              Generated HTML/Markdown reports
└── wordlists/            Default IoT credential lists
```

---

## Supported Firmware Vendors (auto-detection)

Netgear · D-Link · TP-Link · ASUS · Linksys · DrayTek · Belkin · Buffalo · ZyXEL · Huawei · MikroTik · Cisco · Ubiquiti

---

## Tested Environments

- Kali Linux 2023.1 – 2026.x (amd64)
- Firmware architectures: MIPS big-endian, MIPS little-endian, ARMel

---

## License

This project is released for **educational and authorized professional use only**.
See the Legal Disclaimer above for full terms.

---

*IoTStrike — Yechiel Said | https://github.com/CyberSentinel-sys*
