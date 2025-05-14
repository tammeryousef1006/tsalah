#!/bin/bash

# Matterbridge Cross-Distro Installation Script (v5)

set -e

# --- Script Configuration ---
NODE_MAJOR_VERSION="22" # Desired Node.js major version (LTS)

# --- Helper Functions ---
echo_info() {
    echo "[INFO] $1"
}

echo_error() {
    echo "[ERROR] $1" >&2
}

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# --- Sanity Checks ---
if [ "$(id -u)" -ne 0 ]; then
    echo_error "This script must be run as root or with sudo."
    exit 1
fi

# --- Distribution Detection ---
DISTRO=""
PKG_MANAGER=""
INSTALL_CMD=""
UPDATE_CMD=""

if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO="$ID"
    if [ -n "$ID_LIKE" ]; then
        DISTRO_LIKE="$ID_LIKE"
    else
        DISTRO_LIKE="$ID"
    fi
elif command_exists lsb_release; then
    DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    DISTRO_LIKE=$DISTRO
else
    echo_error "Cannot determine Linux distribution."
    exit 1
fi

echo_info "Detected distribution: $DISTRO (like: $DISTRO_LIKE)"

case "$DISTRO_LIKE" in
    debian|ubuntu|devuan|raspbian|pop|linuxmint|kali|zorin)
        PKG_MANAGER="apt"
        UPDATE_CMD="apt-get update"
        INSTALL_CMD="apt-get install -y"
        ;;
    fedora|centos|rhel|rocky|almalinux|nobara)
        if command_exists dnf; then
            PKG_MANAGER="dnf"
            INSTALL_CMD="dnf install -y"
        elif command_exists yum; then
            PKG_MANAGER="yum"
            INSTALL_CMD="yum install -y"
        else
            echo_error "No DNF or YUM package manager found on this $DISTRO_LIKE system."
            exit 1
        fi
        ;;
    arch|manjaro|endeavouros|garuda)
        PKG_MANAGER="pacman"
        INSTALL_CMD="pacman -S --noconfirm --needed"
        ;;
    suse|opensuse|opensuse-tumbleweed|opensuse-leap)
        PKG_MANAGER="zypper"
        INSTALL_CMD="zypper install -y"
        ;;
    *)
        echo_error "Unsupported distribution: $DISTRO (based on $DISTRO_LIKE). Please install dependencies and Node.js manually."
        exit 1
        ;;
esac

echo_info "Using package manager: $PKG_MANAGER"

# --- Install Dependencies ---
echo_info "Installing dependencies (curl, gnupg, ca-certificates)..."
if [ -n "$UPDATE_CMD" ]; then
    $UPDATE_CMD
fi

# Dependency package names might vary slightly
DEPS_TO_INSTALL="curl gnupg ca-certificates"
if [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
    DEPS_TO_INSTALL="curl gnupg ca-certificates"
    # For some older RHEL/CentOS, gnupg might be gnupg2. Attempt gnupg, if fails and gnupg2 exists, use that.
    # This specific logic for gnupg vs gnupg2 can be tricky to get perfect without trying to install first.
    # A simpler approach is to list both if the system handles alternatives, or just try common one.
    # For now, keeping it simple, admin can install manually if specific variant is needed.
    # if ! $INSTALL_CMD gnupg &>/dev/null && command_exists gnupg2; then DEPS_TO_INSTALL="curl gnupg2 ca-certificates"; fi
elif [ "$PKG_MANAGER" == "pacman" ]; then
    DEPS_TO_INSTALL="curl gnupg ca-certificates"
elif [ "$PKG_MANAGER" == "zypper" ]; then
    DEPS_TO_INSTALL="curl gpg2 ca-certificates"
fi
$INSTALL_CMD $DEPS_TO_INSTALL

# --- Install Node.js ---
echo_info "Installing Node.js version $NODE_MAJOR_VERSION LTS..."

install_nodejs_from_source_rpm() {
    echo_info "Attempting Node.js $NODE_MAJOR_VERSION installation via NodeSource RPMs..."
    curl -fsSL "https://rpm.nodesource.com/setup_$NODE_MAJOR_VERSION.x" | bash -
    $INSTALL_CMD nodejs
}

if command_exists node && command_exists npm && [[ "$(node -v)" == "v$NODE_MAJOR_VERSION."* ]]; then
    echo_info "Node.js $NODE_MAJOR_VERSION already installed."
else
    if [ "$PKG_MANAGER" == "apt" ]; then
        echo_info "Setting up NodeSource repository for Node.js $NODE_MAJOR_VERSION..."
        mkdir -p /etc/apt/keyrings
        curl -fsSL "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR_VERSION.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
        apt-get update
        $INSTALL_CMD nodejs
    elif [ "$PKG_MANAGER" == "dnf" ] && ( [[ "$DISTRO" == "fedora" ]] || [[ "$DISTRO_LIKE" == *"rhel"* && "$(echo "${VERSION_ID:-0}" | cut -d. -f1)" -ge 8 ]] || [[ "$DISTRO_LIKE" == *"centos"* && "$(echo "${VERSION_ID:-0}" | cut -d. -f1)" -ge 8 ]] ); then
        echo_info "Attempting to install Node.js $NODE_MAJOR_VERSION using dnf module..."
        if ! dnf module install -y "nodejs:$NODE_MAJOR_VERSION/common"; then
            echo_info "DNF module install for nodejs:$NODE_MAJOR_VERSION failed or module not found. Falling back to NodeSource RPMs."
            install_nodejs_from_source_rpm
        fi
    elif [ "$PKG_MANAGER" == "yum" ]; then # Older RHEL/CentOS that only have yum
        install_nodejs_from_source_rpm
    elif [ "$PKG_MANAGER" == "pacman" ]; then
        echo_info "Installing Node.js using pacman (will install latest LTS or stable)..."
        $INSTALL_CMD nodejs npm
        if ! [[ "$(node -v)" == "v$NODE_MAJOR_VERSION."* ]] && ! [[ "$(node -v | cut -d. -f1 | sed 's/v//')" -ge 18 ]]; then 
             echo_info "[WARNING] Installed Node.js version $(node -v) is not $NODE_MAJOR_VERSION or >=18. Matterbridge might work, but $NODE_MAJOR_VERSION LTS is recommended."; 
        fi
    elif [ "$PKG_MANAGER" == "zypper" ]; then
        echo_info "Installing Node.js $NODE_MAJOR_VERSION using zypper..."
        if ! $INSTALL_CMD "nodejs$NODE_MAJOR_VERSION"; then
            echo_info "[WARNING] Could not install nodejs$NODE_MAJOR_VERSION directly. Attempting generic 'nodejs'. You might get a different version."
            $INSTALL_CMD nodejs npm
        fi
    else # Fallback for other distros or if specific methods fail
        echo_info "Attempting generic Node.js installation from official binaries..."
        ARCH=""
        case "$(uname -m)" in
            x86_64) ARCH="x64" ;;
            aarch64) ARCH="arm64" ;;
            armv7l) ARCH="armv7l" ;;
            *)
                echo_error "Unsupported architecture for generic Node.js install: $(uname -m)"
                exit 1
                ;;
        esac
        # Try to get the exact latest version for the major release
        NODE_VERSION_LINE=$(curl -sL https://nodejs.org/dist/latest-v$NODE_MAJOR_VERSION.x/ | grep -o "node-v$NODE_MAJOR_VERSION\.[0-9]*\.[0-9]*-linux-$ARCH.tar.xz" | head -n 1)
        if [ -z "$NODE_VERSION_LINE" ]; then 
            echo_error "Could not find Node.js v$NODE_MAJOR_VERSION binary for $ARCH from official site."; 
            exit 1; 
        fi
        NODE_TARBALL_FILENAME="$NODE_VERSION_LINE"
        echo_info "Downloading $NODE_TARBALL_FILENAME..."
        curl -fsSL "https://nodejs.org/dist/latest-v$NODE_MAJOR_VERSION.x/$NODE_TARBALL_FILENAME" -o "/tmp/$NODE_TARBALL_FILENAME"
        echo_info "Extracting to /usr/local..."
        tar -xf "/tmp/$NODE_TARBALL_FILENAME" -C /usr/local --strip-components=1
        rm "/tmp/$NODE_TARBALL_FILENAME"
        export PATH="/usr/local/bin:$PATH" # Ensure it's in PATH for this session
    fi
fi

if ! command_exists node || ! command_exists npm; then
    echo_error "Node.js or npm installation failed or not found in PATH."
    exit 1
fi
echo_info "Node.js version: $(node -v), npm version: $(npm -v)"

# --- Install Matterbridge ---
echo_info "Installing Matterbridge globally using npm..."
npm install -g matterbridge --omit=dev

# --- Determine Effective User and Home Directory ---
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    EFFECTIVE_USER="$SUDO_USER"
else
    EFFECTIVE_USER="root"
fi
EFFECTIVE_HOME=$(getent passwd "$EFFECTIVE_USER" | cut -d: -f6)

if [ -z "$EFFECTIVE_HOME" ]; then
    echo_error "Could not determine home directory for user $EFFECTIVE_USER."
    exit 1
fi
echo_info "Configuring Matterbridge for user: $EFFECTIVE_USER (Home: $EFFECTIVE_HOME)"

# --- Create Directories and Set Permissions ---
echo_info "Creating Matterbridge directories..."
mkdir -p "$EFFECTIVE_HOME/.matterbridge"
mkdir -p "$EFFECTIVE_HOME/Matterbridge"

echo_info "Setting permissions for Matterbridge directories..."
chown -R "$EFFECTIVE_USER:$EFFECTIVE_USER" "$EFFECTIVE_HOME/.matterbridge" "$EFFECTIVE_HOME/Matterbridge"

# --- Get Matterbridge Executable Path ---
NPM_PREFIX=$(npm config get prefix)
MB_EXEC_PATH="$NPM_PREFIX/bin/matterbridge"

if [ ! -f "$MB_EXEC_PATH" ]; then
    echo_info "Matterbridge executable not found at $MB_EXEC_PATH. Trying 'which matterbridge'..."
    MB_EXEC_PATH_WHICH=$(which matterbridge)
    if [ -f "$MB_EXEC_PATH_WHICH" ]; then
        echo_info "Found matterbridge via 'which' at: $MB_EXEC_PATH_WHICH. Using this path."
        MB_EXEC_PATH="$MB_EXEC_PATH_WHICH"
    else
        echo_error "Could not locate matterbridge executable. Please check npm installation."
        exit 1
    fi
fi

# --- Create systemd Service File ---
if ! command_exists systemctl; then
    echo_error "systemctl command not found. This script currently only supports systemd-based systems for service creation."
    echo_info "Matterbridge is installed. Please configure it to run on startup manually."
    exit 0 # Exit gracefully as Matterbridge itself is installed
fi

echo_info "Creating systemd service file for Matterbridge..."

NODE_BIN_DIR=$(dirname "$(which node)")
SERVICE_PATH_ENV="$NODE_BIN_DIR:$NPM_PREFIX/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

cat << EOF > /etc/systemd/system/matterbridge.service
[Unit]
Description=Matterbridge
After=network-online.target

[Service]
Type=simple
User=$EFFECTIVE_USER
Group=$(id -gn "$EFFECTIVE_USER")
WorkingDirectory=$EFFECTIVE_HOME/Matterbridge
ExecStart=$MB_EXEC_PATH -service
Restart=always
RestartSec=10s
StandardOutput=inherit
StandardError=inherit
Environment="HOME=$EFFECTIVE_HOME"
Environment="USER=$EFFECTIVE_USER"
Environment="PATH=$SERVICE_PATH_ENV"

[Install]
WantedBy=multi-user.target
EOF

# --- Reload systemd, Enable and Start Service ---
echo_info "Reloading systemd daemon, enabling and starting Matterbridge service..."
systemctl daemon-reload
systemctl enable matterbridge.service
systemctl start matterbridge.service

# --- Final Report ---
echo_info "---------------------------------------------------------------------"
echo_info "Matterbridge installation and service setup complete."
echo_info "Service configured to run as user: $EFFECTIVE_USER"
echo_info "Working directory: $EFFECTIVE_HOME/Matterbridge"
echo_info "Configuration directory: $EFFECTIVE_HOME/.matterbridge"
echo_info "Matterbridge executable: $MB_EXEC_PATH"
echo_info "Node.js path for service: $NODE_BIN_DIR"
echo_info ""
echo_info "To check status: sudo systemctl status matterbridge.service"
echo_info "To see logs: sudo journalctl -u matterbridge.service -f"
echo_info "---------------------------------------------------------------------"

exit 0

