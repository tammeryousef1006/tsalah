#!/bin/bash

# Matterbridge Cross-Distro Uninstallation Script (v4)

set -e

# --- Helper Functions ---
echo_info() {
    echo "[INFO] $1"
}

echo_error() {
    echo "[ERROR] $1" >&2
}

# --- Bash Shell Check ---
if [ -z "$BASH_VERSION" ]; then
    echo_error "This script is designed to be run with Bash."
    echo_error "Please execute it using: bash $0"
    exit 1
fi

# --- Sanity Checks ---
if [ "$(id -u)" -ne 0 ]; then
    echo_error "This script must be run as root or with sudo."
    exit 1
fi

# --- Stop and Disable systemd Service ---
echo_info "Attempting to stop and disable Matterbridge systemd service..."
if command -v systemctl &> /dev/null; then
    if systemctl is-active --quiet matterbridge.service; then
        systemctl stop matterbridge.service || echo_info "Matterbridge service could not be stopped (maybe already stopped)."
    else
        echo_info "Matterbridge service is not active."
    fi
    if systemctl is-enabled --quiet matterbridge.service; then
        systemctl disable matterbridge.service || echo_info "Matterbridge service could not be disabled (maybe already disabled)."
    else
        echo_info "Matterbridge service is not enabled."
    fi
else
    echo_info "systemctl not found. Skipping systemd service stop/disable. If you used a different init system (e.g., OpenRC on Alpine), please stop/disable Matterbridge manually."
    # Alpine specific OpenRC check (example, might need rc-service, rc-update)
    if command -v rc-service &> /dev/null && [ -f /etc/init.d/matterbridge ]; then
        echo_info "Attempting to stop Matterbridge OpenRC service (Alpine)..."
        rc-service matterbridge stop || echo_info "Failed to stop matterbridge OpenRC service."
        echo_info "Attempting to remove Matterbridge from OpenRC default runlevel (Alpine)..."
        rc-update del matterbridge default || echo_info "Failed to remove matterbridge from OpenRC default runlevel."
    fi
fi

# --- Remove systemd Service File ---
SERVICE_FILE_SYSTEMD="/etc/systemd/system/matterbridge.service"
SERVICE_FILE_OPENRC="/etc/init.d/matterbridge"

if [ -f "$SERVICE_FILE_SYSTEMD" ]; then
    echo_info "Removing Matterbridge systemd service file: $SERVICE_FILE_SYSTEMD..."
    rm -f "$SERVICE_FILE_SYSTEMD"
    if command -v systemctl &> /dev/null; then
        echo_info "Reloading systemd daemon..."
        systemctl daemon-reload
        systemctl reset-failed
    fi
elif [ -f "$SERVICE_FILE_OPENRC" ]; then
    echo_info "Removing Matterbridge OpenRC service file: $SERVICE_FILE_OPENRC (Alpine)..."
    rm -f "$SERVICE_FILE_OPENRC"
else
    echo_info "Matterbridge service file (systemd or OpenRC) not found."
fi


# --- Uninstall Matterbridge npm Package ---
if command -v npm &> /dev/null; then
    echo_info "Checking if Matterbridge npm package is installed globally..."
    if npm list -g --depth=0 matterbridge &> /dev/null; then
        echo_info "Uninstalling Matterbridge npm package globally..."
        npm uninstall -g matterbridge
    else
        echo_info "Matterbridge npm package not found globally."
    fi
else
    echo_info "npm command not found. Cannot uninstall Matterbridge npm package."
    echo_info "If Node.js and npm were installed, ensure npm is in the PATH for root."
fi

# --- Determine Effective User and Home for Directory Removal ---
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    EFFECTIVE_USER_UNINSTALL="$SUDO_USER"
else
    EFFECTIVE_USER_UNINSTALL="root"
fi

USERS_TO_CHECK=()
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    USERS_TO_CHECK+=("$SUDO_USER")
fi
USERS_TO_CHECK+=("root") 

UNIQUE_USERS_TO_CHECK=($(printf "%s\n" "${USERS_TO_CHECK[@]}" | sort -u))

for USER_TO_CHECK in "${UNIQUE_USERS_TO_CHECK[@]}"; do
    EFFECTIVE_HOME_UNINSTALL=$(getent passwd "$USER_TO_CHECK" | cut -d: -f6)
    if [ -z "$EFFECTIVE_HOME_UNINSTALL" ] || [ ! -d "$EFFECTIVE_HOME_UNINSTALL" ]; then
        echo_info "Could not determine or access home directory for user $USER_TO_CHECK. Skipping directory removal for this user."
        continue
    fi

    CONFIG_DIR_TO_REMOVE="$EFFECTIVE_HOME_UNINSTALL/.matterbridge"
    WORKING_DIR_TO_REMOVE="$EFFECTIVE_HOME_UNINSTALL/Matterbridge"

    echo_info "Checking for Matterbridge directories for user: $USER_TO_CHECK (Home: $EFFECTIVE_HOME_UNINSTALL)"

    if [ -d "$CONFIG_DIR_TO_REMOVE" ]; then
        echo_info "Removing Matterbridge configuration directory: $CONFIG_DIR_TO_REMOVE ..."
        rm -rf "$CONFIG_DIR_TO_REMOVE"
    else
        echo_info "Matterbridge configuration directory $CONFIG_DIR_TO_REMOVE not found for user $USER_TO_CHECK."
    fi

    if [ -d "$WORKING_DIR_TO_REMOVE" ]; then
        echo_info "Removing Matterbridge working directory: $WORKING_DIR_TO_REMOVE ..."
        rm -rf "$WORKING_DIR_TO_REMOVE"
    else
        echo_info "Matterbridge working directory $WORKING_DIR_TO_REMOVE not found for user $USER_TO_CHECK."
    fi
done

# --- Final Notes ---
echo_info "---------------------------------------------------------------------"
echo_info "Matterbridge uninstallation attempt complete."
echo_info "Node.js has NOT been uninstalled by this script."
echo_info "If Node.js was installed specifically for Matterbridge and is no longer needed,"
echo_info "you may need to remove it manually depending on how it was installed."
echo_info "Common Node.js removal steps (use with caution and adapt to your distro/install method):"
echo_info "  - If installed via NodeSource on Debian/Ubuntu: sudo apt-get purge nodejs && sudo rm /etc/apt/sources.list.d/nodesource.list"
echo_info "  - If installed via dnf module on Fedora/RHEL: sudo dnf module reset nodejs && sudo dnf remove nodejs"
echo_info "  - If installed via pacman: sudo pacman -Rns nodejs npm"
echo_info "  - If installed via zypper: sudo zypper remove nodejs<version>"
echo_info "  - If installed from binaries (e.g., to /usr/local): sudo rm -rf /usr/local/bin/node /usr/local/bin/npm /usr/local/lib/node_modules /usr/local/include/node"
echo_info "  - On Alpine, if installed via apk: sudo apk del nodejs npm"
echo_info "---------------------------------------------------------------------"

exit 0

