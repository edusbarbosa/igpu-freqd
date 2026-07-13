#!/bin/bash
# /*
#  * igpu-freqd installer
#  * sets up the dynamic frequency scaling daemon for intel igpus
#  */

set -e

# /*
#  * visual output styles and color codes
#  */
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_BLUE="\033[34m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_RESET="\033[0m"

info()    { echo -e "${C_BLUE}info${C_RESET}  $*"; }
success() { echo -e "${C_GREEN}done${C_RESET}  $*"; }
warn()    { echo -e "${C_YELLOW}warn${C_RESET}  $*"; }
error()   { echo -e "${C_RED}err!${C_RESET}  $*"; exit 1; }
header()  { echo -e "\n${C_BOLD}:: $*${C_RESET}"; }

# /*
#  * entry point and privilege check
#  */
echo -e "${C_BOLD}igpu-freqd installer${C_RESET}"
echo "---------------------------------------------------------"

if [[ "$EUID" -ne 0 ]]; then
    error "this script must be run as root"
fi

# /*
#  * environment preparation and cleanup
#  * removes existing installation to ensure a clean update
#  */
header "preparing environment"

info "checking for existing installation..."
if systemctl is-active --quiet igpu-freqd.service 2>/dev/null || [ -f "/usr/local/bin/igpu-freqd" ]; then
    info "existing installation found, removing for update..."
    systemctl disable --now igpu-freqd.service 2>/dev/null || true
    rm -f /etc/systemd/system/igpu-freqd.service
    rm -f /usr/local/bin/igpu-freqd
    success "previous version removed"
else
    info "no previous installation detected"
fi

# /*
#  * dependency resolution and package installation
#  */
header "checking dependencies"

info "detecting package manager..."
if command -v dnf &> /dev/null; then
    dnf install -y intel-gpu-tools
elif command -v apt-get &> /dev/null; then
    apt-get update && apt-get install -y intel-gpu-tools
elif command -v pacman &> /dev/null; then
    pacman -Sy --noconfirm intel-gpu-tools
elif command -v zypper &> /dev/null; then
    zypper in -y intel-gpu-tools
else
    error "unsupported package manager. please install 'intel-gpu-tools' manually."
fi

if ! command -v intel_gpu_top &> /dev/null; then
    error "intel-gpu-tools installation failed or not found in path"
fi

success "dependencies satisfied"

# /*
#  * file installation and configuration setup
#  */
header "installing files"

info "downloading binary to /usr/local/bin..."
curl -fsSL https://raw.githubusercontent.com/edusbarbosa/igpu-freqd/main/igpu-freqd -o /usr/local/bin/igpu-freqd
chmod +x /usr/local/bin/igpu-freqd

info "creating default configuration at /etc/igpu-freqd.conf..."
if [ ! -f "/etc/igpu-freqd.conf" ]; then
    cat > /etc/igpu-freqd.conf << 'EOF'
# /*
#  * igpu-freqd configuration
#  * all values are in seconds, mhz or celsius
#  */
POLL_RATE=0.4
TEMP_LIMIT_C=90
HYSTERESIS=30
INTEL_GPU_TOP_TIMEOUT=0.3
INTEL_GPU_TOP_SAMPLES=100
FALLBACK_FREQ_MHZ=800
MAX_FAILURES=3
SMOOTHING_WINDOW=5
ALPHA_TEMP=0.3
SLEW_RATE_LIMIT=100
THERMAL_DECAY_FACTOR=0.05
FALLBACK_TEMP_C=40

# /*
#  * log_level: 0=changes, 1=heartbeat (every n cycles), 2=verbose
#  */
LOG_LEVEL=0
HEARTBEAT_CYCLES=10
EOF
    chmod 644 /etc/igpu-freqd.conf
    info "new configuration file created"
else
    info "preserving existing configuration at /etc/igpu-freqd.conf"
fi

info "configuring systemd service unit..."
cat << 'EOF' > /etc/systemd/system/igpu-freqd.service
[Unit]
Description=Intel iGPU Dynamic Frequency Scaling Daemon
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/igpu-freqd
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal
SyslogIdentifier=igpu-freqd

[Install]
WantedBy=multi-user.target
EOF

success "files installed successfully"

# /*
#  * systemd service activation
#  */
header "activating service"

info "reloading systemd daemon..."
systemctl daemon-reload

success "installation complete"

info "enabling and starting igpu-freqd..."
systemctl enable igpu-freqd.service >/dev/null
systemctl start igpu-freqd.service >/dev/null 2>&1

success "service is now active\n"

echo "---------------------------------------------------------"
echo -e "monitor logs with: ${C_BOLD}journalctl -u igpu-freqd -f${C_RESET}"
echo "---------------------------------------------------------"
