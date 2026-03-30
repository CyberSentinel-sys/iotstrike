# IoTStrike: Universal IoT Security Framework

```text
  ___   ___   _____   ___   _             _  _
 |_ _| / _ \|_   _|/ __|| |_  _ _   (_)| |__ ___
  | | | (_) | | |  \__ \|  _|| '_|  | || / // -_)
 |___| \___/  |_|  |___/ \__||_|    |_||_\_\\__|

  Emulate · Scan · CVE Intel · Sessions · Web UI · Reports
```

**Lead Architect:** Yechiel Said 🛡️

**Professional Inquiries:** yechielstudy@gmail.com

**Latest Technical Audit:** [The 2026 AI & SEO Infrastructure Breakdown](https://medium.com/@yechielbiz/semrush-review-your-all-in-one-seo-toolkit-for-digital-dominance-8c7a7bee7d43)

## 🛡️ Strategic Context & Professional Audit

IoTStrike is a core component of my 2026 research into Sovereign AI Infrastructure and Red Team Automation. As a Cybersecurity Specialist at 8alert.com and Founder of MedShield AI™, I believe that modern security requires a "Shift-Left" approach to IoT firmware. This tool was built to bridge the gap between static firmware analysis and active exploitation.

## The "Zero-Cost" Infrastructure Philosophy

I recently published a comprehensive technical audit on Medium where I discuss how I apply the same "Red Team" mindset used in IoTStrike to build secure, $0-overhead business infrastructures using AI.

👉 [Read the Full Audit on Medium](https://medium.com/@yechielbiz/semrush-review-your-all-in-one-seo-toolkit-for-digital-dominance-8c7a7bee7d43)

## ⚠️ Legal Disclaimer

IoTStrike is intended exclusively for authorized security research, educational purposes, and professional penetration testing engagements. Unauthorized use against systems without explicit permission is illegal. The author accepts no liability for misuse.

## 🛠️ Core Capabilities

| Module | Technical Execution | Integrated Tools |
|--------|---------------------|------------------|
| Firmware Emulation | Multi-Architecture (MIPS/ARM) extraction & QEMU orchestration | Firmadyne, FirmAE, EMBA |
| Vulnerability Scanning | Automated port mapping, web fuzzing, & default credential testing | Nmap, Nikto, Hydra |
| CVE Intelligence | Real-time REST API integration for NIST NVD vulnerability correlation | NVD API v2 |
| Web Dashboard | Live telemetry & session monitoring via Flask-based Web UI | Flask, JS Auto-Refresh |
| Reporting | Automated Markdown/HTML generation for professional C-Level delivery | Python-Pandas |

## 🚀 Deployment & Installation

### Standard Installation

Run the setup script on a clean Kali Linux (2023–2026) environment. The script automates the complex configuration of PostgreSQL, QEMU kernels, and Firmadyne dependencies.

```bash
# Clone the repository and execute the setup
git clone https://github.com/CyberSentinel-sys/iotstrike.git
cd iotstrike
sudo bash Iotstrike.sh
```

### Interactive Mode

Launch the framework and follow the menu-driven prompts to select your target firmware:

```bash
sudo bash /opt/iotstrike/IoTStrike.sh
```

## 🌐 Web API & Automation

IoTStrike includes a built-in Flask API Server for remote orchestration.

**Start the Server:**

```bash
sudo python3 /opt/iotstrike/iot_web_server.py --port 8080
```

**Query Status via CLI:**

```bash
# Authenticate using the one-time key printed at startup
curl -H "Authorization: Bearer <YOUR_API_KEY>" http://127.0.0.1:8080/api/status
```

## 📁 Architecture Overview

```
/opt/iotstrike/
├── IoTStrike.sh           # Main Orchestrator
├── iot_web_server.py      # Flask API Endpoint
├── firmadyne/             # QEMU / Firmware Kernels
├── binwalk/               # Extraction Engine
├── logs/                  # Real-time Telemetry
├── reports/               # HTML/MD Assessment Exports
└── sessions/              # Persistent Pentest State
```

## 🤝 Connect & Collaborate

I am actively looking for collaborators interested in AI-Driven Vulnerability Research and AppSec Automation.

- **LinkedIn:** [Yechiel Said](https://www.linkedin.com/in/yechielsaid/)
- **Technical Blog:** [Yechiel on Medium](https://www.google.com/search?q=https://medium.com/%40yechielbiz)
- **Email:** yechielstudy@gmail.com

---

IoTStrike — Part of the CyberSentinel Ecosystem | 2026

https://github.com/user-attachments/assets/80db3b92-078d-44f3-adb3-26ffdc8b7749


