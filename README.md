# IoTStrike: Universal IoT Security Framework

```text
  ___   ___   _____   ___   _             _  _
 |_ _| / _ \|_   _|/ __|| |_  _ _   (_)| |__ ___
  | | | (_) | | |  \__ \|  _|| '_|  | || / // -_)
 |___| \___/  |_|  |___/ \__||_|    |_||_\_\\__|

  Emulate · Scan · CVE Intel · Sessions · Web UI · Reports
Lead Architect: Yechiel Said 🛡️Professional Inquiries: yechielstudy@gmail.comLatest Technical Audit: The 2026 AI & SEO Infrastructure Breakdown🛡️ Strategic Context & Professional AuditIoTStrike is a core component of my 2026 research into Sovereign AI Infrastructure and Red Team Automation. As a Cybersecurity Specialist at 8alert.com and Founder of MedShield AI™, I believe that modern security requires a "Shift-Left" approach to IoT firmware. This tool was built to bridge the gap between static firmware analysis and active exploitation.The "Zero-Cost" Infrastructure PhilosophyI recently published a comprehensive technical audit on Medium where I discuss how I apply the same "Red Team" mindset used in IoTStrike to build secure, $0-overhead business infrastructures using AI.👉 Read the Full Audit on Medium⚠️ Legal DisclaimerIoTStrike is intended exclusively for authorized security research, educational purposes, and professional penetration testing engagements where explicit written permission has been obtained. Unauthorized use against systems without permission is illegal. The author accepts no liability for misuse.🛠️ Core CapabilitiesModuleTechnical ExecutionIntegrated ToolsFirmware EmulationMulti-Architecture (MIPS/ARM) extraction & QEMU orchestrationFirmadyne, FirmAE, EMBAVulnerability ScanningAutomated port mapping, web fuzzing, & default credential testingNmap, Nikto, HydraCVE IntelligenceReal-time REST API integration for NIST NVD vulnerability correlationNVD API v2Web DashboardLive telemetry & session monitoring via Flask-based Web UIFlask, JS Auto-RefreshReportingAutomated Markdown/HTML generation for professional C-Level deliveryPython-Pandas🚀 Deployment & InstallationStandard InstallationRun the setup script on a clean Kali Linux (2023–2026) environment. The script automates the complex configuration of PostgreSQL, QEMU kernels, and Firmadyne dependencies.Bash# Clone the repository and execute the setup
git clone [https://github.com/CyberSentinel-sys/iotstrike.git](https://github.com/CyberSentinel-sys/iotstrike.git)
cd iotstrike
sudo bash Iotstrike.sh
Interactive ModeLaunch the framework and follow the menu-driven prompts to select your target firmware:Bashsudo bash /opt/iotstrike/IoTStrike.sh
🌐 Web API & AutomationIoTStrike includes a built-in Flask API Server for remote orchestration.Start the Server:Bashsudo python3 /opt/iotstrike/iot_web_server.py --port 8080
Query Status via CLI:Bash# Authenticate using the one-time key printed at startup
curl -H "Authorization: Bearer <YOUR_API_KEY>" [http://127.0.0.1:8080/api/status](http://127.0.0.1:8080/api/status)
📁 Architecture OverviewPlaintext/opt/iotstrike/
├── IoTStrike.sh           # Main Orchestrator
├── iot_web_server.py      # Flask API Endpoint
├── firmadyne/             # QEMU / Firmware Kernels
├── binwalk/               # Extraction Engine
├── logs/                  # Real-time Telemetry
├── reports/               # HTML/MD Assessment Exports
└── sessions/              # Persistent Pentest State
🤝 Connect & CollaborateI am actively looking for collaborators interested in AI-Driven Vulnerability Research and AppSec Automation.LinkedIn: Yechiel SaidTechnical Blog: Yechiel on MediumEmail: yechielstudy@gmail.comIoTStrike — Part of the CyberSentinel Ecosystem | 2026
