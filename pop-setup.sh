#!/usr/bin/env bash
#
# Ubuntu 24.04 LTS Kiosk Setup Script for 4Youth
#
# Locks down an Ubuntu GNOME laptop so the user can only use Chrome
# with shortcuts to approved websites. Auto-login, no terminal,
# no file manager, no settings access.
#
# Usage: ./pop-setup.sh [OPTIONS]
#

set -euo pipefail

# Ensure gsettings can talk to the GNOME session dbus
# (needed when running via curl|bash or non-interactive shells)
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    DBUS_PID=$(pgrep -u "$USER" gnome-session 2>/dev/null || pgrep -u "$USER" gnome-shell 2>/dev/null || true)
    if [[ -n "$DBUS_PID" ]]; then
        eval "$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/"$DBUS_PID"/environ 2>/dev/null | tr '\0' '\n')"
        export DBUS_SESSION_BUS_ADDRESS
    fi
fi

# Forgejo configuration
GITEA_BASE="https://git.technoliga.co.uk"
GITEA_REPO="jon/pop-setup"
GITEA_BRANCH="main"
SCRIPT_URL="${GITEA_BASE}/${GITEA_REPO}/raw/branch/${GITEA_BRANCH}/pop-setup.sh"
CONFIG_URL="${GITEA_BASE}/${GITEA_REPO}/raw/branch/${GITEA_BRANCH}/config.json"
ASSETS_URL="${GITEA_BASE}/${GITEA_REPO}/raw/branch/${GITEA_BRANCH}/icons"

# Device tracking API
DEVICE_API="https://popos.4youth.org.uk/api.php"

# Local install paths for assets
ICON_DIR="/usr/share/icons/4youth"
WALLPAPER_DIR="/usr/share/backgrounds/4youth"
CONFIG_DIR="$HOME/.config/4youth"
CONFIG_FILE="$CONFIG_DIR/config.json"

# 4Youth brand colour (from logo)
BRAND_COLOUR="#1DA1D4"

# Delay tracking
MAX_DELAYS=3
DELAY_FILE="$HOME/.pop-setup-delay-count"
SKIP_FILE="$HOME/.pop-setup-skipped-version"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Safety checks
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run this script as root. Run as the target user with sudo access."
        exit 1
    fi
}

check_ubuntu() {
    if ! grep -qi 'ubuntu' /etc/os-release 2>/dev/null; then
        log_warn "This script is designed for Ubuntu 24.04 LTS. Detected: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2)"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || exit 1
    fi
}

backup_config() {
    local file="$1"
    if [[ -e "$file" ]]; then
        local backup_dir="$HOME/.pop-setup-backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        cp -r "$file" "$backup_dir/$(basename "$file").bak"
        log_info "Backed up: $file"
    fi
}

# ============================================================
# 1. System Updates
# ============================================================
fix_chrome_repo() {
    # Chrome's installer can add its own .list / .sources files that conflict
    # with the one we create. Clean up any conflicting entries before apt update.
    local dominated=false
    for f in /etc/apt/sources.list.d/google-chrome*.list /etc/apt/sources.list.d/google-chrome*.sources; do
        [[ -f "$f" ]] || continue
        if [[ "$f" != "/etc/apt/sources.list.d/chrome.list" ]]; then
            sudo rm -f "$f"
            dominated=true
        fi
    done
    if [[ -f "/etc/apt/sources.list.d/chrome.list" ]]; then
        if grep -q "Signed-By" "/etc/apt/sources.list.d/chrome.list" && ! grep -q "signed-by=/usr/share/keyrings/chrome.gpg" "/etc/apt/sources.list.d/chrome.list" 2>/dev/null; then
            sudo rm -f "/etc/apt/sources.list.d/chrome.list"
            dominated=true
        fi
    fi
    if [[ "$dominated" == "true" ]]; then
        log_info "Cleaned up conflicting Chrome repo entries"
    fi
}

install_prerequisites() {
    log_info "Installing prerequisites..."
    export DEBIAN_FRONTEND=noninteractive
    fix_chrome_repo
    sudo -E apt update
    sudo -E apt install -y curl jq openssh-server
    sudo systemctl enable ssh
    sudo systemctl start ssh
    log_success "Prerequisites installed (including SSH)"
}

update_system() {
    log_info "Updating system packages..."
    fix_chrome_repo
    export DEBIAN_FRONTEND=noninteractive
    sudo -E apt update
    sudo -E apt upgrade -y --fix-missing -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || {
        log_warn "Some packages failed to upgrade — retrying..."
        sudo -E apt update
        sudo -E apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || log_warn "Some upgrades failed — continuing anyway"
    }
    sudo -E apt autoremove -y
    log_success "System updated"
}

# ============================================================
# 2. Install Chrome (the only app users need)
# ============================================================
install_chrome() {
    log_info "Installing Google Chrome..."

    CHROME_SOURCE="/etc/apt/sources.list.d/chrome.list"

    # Fix conflicting Signed-By if present
    if [[ -f "$CHROME_SOURCE" ]]; then
        if grep -q "Signed-By" "$CHROME_SOURCE" && ! grep -q "signed-by=/usr/share/keyrings/chrome.gpg" "$CHROME_SOURCE" 2>/dev/null; then
            sudo rm -f "$CHROME_SOURCE"
        fi
    fi

    if ! command -v google-chrome &> /dev/null; then
        curl -sL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/chrome.gpg 2>/dev/null || true
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee "$CHROME_SOURCE"
        sudo apt update
        sudo apt install -y google-chrome-stable
        log_success "Google Chrome installed"
    else
        log_success "Google Chrome already installed"
    fi

    # Chrome's installer adds its own repo file — clean up conflicts
    fix_chrome_repo

    # Set Chrome as default browser
    xdg-settings set default-web-browser google-chrome.desktop 2>/dev/null || true
    xdg-mime default google-chrome.desktop x-scheme-handler/http 2>/dev/null || true
    xdg-mime default google-chrome.desktop x-scheme-handler/https 2>/dev/null || true

    log_success "Chrome set as default browser"
}

# ============================================================
# 3. Configure Chrome Managed Policies
# ============================================================
configure_chrome_policies() {
    log_info "Configuring Chrome managed policies..."

    sudo mkdir -p /etc/opt/chrome/policies/managed
    sudo tee /etc/opt/chrome/policies/managed/4youth-policy.json > /dev/null << 'EOF'
{
    "PasswordManagerEnabled": false,
    "AutofillCreditCardEnabled": false,
    "AutofillAddressEnabled": false,
    "BrowserSigninMode": 0,
    "SyncDisabled": true,
    "IncognitoModeAvailability": 1
}
EOF

    log_success "Chrome policies configured (password saving disabled, sync disabled)"
}

# ============================================================
# 4. Configure Power Management
# ============================================================
configure_power() {
    log_info "Configuring power management..."

    if ! command -v tlp &> /dev/null; then
        sudo apt install -y tlp tlp-rdw
        sudo tlp start 2>/dev/null || log_warn "Could not start TLP"
    fi

    log_success "Power management configured"
}

# ============================================================
# 5. Configure Auto-login
# ============================================================
configure_autologin() {
    log_info "Configuring auto-login..."

    local username="$USER"
    local gdm_conf="/etc/gdm3/custom.conf"

    backup_config "$gdm_conf"

    if [[ -f "$gdm_conf" ]]; then
        sudo sed -i '/^AutomaticLogin/d' "$gdm_conf"
        sudo sed -i '/^AutomaticLoginEnable/d' "$gdm_conf"

        if grep -q '^\[daemon\]' "$gdm_conf"; then
            sudo sed -i '/^\[daemon\]/a AutomaticLoginEnable = true\nAutomaticLogin = '"$username" "$gdm_conf"
        else
            printf '\n[daemon]\nAutomaticLoginEnable = true\nAutomaticLogin = %s\n' "$username" | sudo tee -a "$gdm_conf" > /dev/null
        fi
        log_success "Auto-login enabled for: $username"
    else
        log_warn "GDM config not found at $gdm_conf"
    fi

}

# ============================================================
# 6. Download Config & Install Assets
# ============================================================
download_config() {
    log_info "Downloading configuration..."

    mkdir -p "$CONFIG_DIR"

    # Ensure jq is available for parsing config
    if ! command -v jq &> /dev/null; then
        sudo apt install -y jq
    fi

    curl -sL "$CONFIG_URL" -o "$CONFIG_FILE.tmp"
    if [[ -s "$CONFIG_FILE.tmp" ]]; then
        # Validate it's valid JSON
        if jq empty "$CONFIG_FILE.tmp" 2>/dev/null; then
            mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            log_success "Configuration downloaded"
        else
            rm -f "$CONFIG_FILE.tmp"
            log_warn "Downloaded config is not valid JSON — keeping existing config"
        fi
    else
        rm -f "$CONFIG_FILE.tmp"
        log_warn "Could not download config.json — using existing config"
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "No config.json available — cannot continue"
        exit 1
    fi
}

install_assets() {
    log_info "Installing icons and assets..."

    sudo mkdir -p "$ICON_DIR" "$WALLPAPER_DIR"

    # Download icons referenced in config
    local icon_files
    icon_files=$(jq -r '.bookmarks[].icon' "$CONFIG_FILE" | sort -u)

    while IFS= read -r icon_name; do
        [[ -z "$icon_name" || "$icon_name" == "null" ]] && continue
        local local_name
        local_name=$(echo "$icon_name" | tr '[:upper:]' '[:lower:]')
        local dest="$ICON_DIR/$local_name"
        curl -sL "${ASSETS_URL}/${icon_name}" -o "/tmp/${local_name}"
        if [[ -s "/tmp/${local_name}" ]]; then
            sudo mv "/tmp/${local_name}" "$dest"
            log_info "Installed icon: $icon_name"
        else
            rm -f "/tmp/${local_name}"
            log_warn "Failed to download icon: $icon_name"
        fi
    done <<< "$icon_files"

    # Download wallpaper if config says to use one
    local wallpaper_setting
    wallpaper_setting=$(jq -r '.wallpaper // "brand-colour"' "$CONFIG_FILE")

    if [[ "$wallpaper_setting" != "brand-colour" ]]; then
        curl -sL "${ASSETS_URL}/${wallpaper_setting}" -o "/tmp/wallpaper.png"
        if [[ -s "/tmp/wallpaper.png" ]]; then
            sudo mv "/tmp/wallpaper.png" "$WALLPAPER_DIR/wallpaper.png"
            log_info "Installed wallpaper"
        else
            rm -f "/tmp/wallpaper.png"
            log_warn "Wallpaper image not found — will fall back to brand colour"
        fi
    else
        # Clean up any old wallpaper if admin switched back to brand colour
        sudo rm -f "$WALLPAPER_DIR/wallpaper.png"
    fi

    log_success "Assets installed"
}

# ============================================================
# 7. Create Desktop Shortcuts (the dock icons)
# ============================================================
create_desktop_shortcuts() {
    log_info "Creating desktop shortcuts..."

    local apps_dir="$HOME/.local/share/applications"
    mkdir -p "$apps_dir"

    # Remove old 4youth- shortcuts so removed bookmarks disappear
    rm -f "$apps_dir"/4youth-*.desktop

    # Desktop file IDs for dock pinning (in order)
    local dock_ids=()

    local count
    count=$(jq '.bookmarks | length' "$CONFIG_FILE")

    for (( i=0; i<count; i++ )); do
        local name url icon_file
        name=$(jq -r ".bookmarks[$i].name" "$CONFIG_FILE")
        url=$(jq -r ".bookmarks[$i].url" "$CONFIG_FILE")
        icon_file=$(jq -r ".bookmarks[$i].icon" "$CONFIG_FILE")

        # Resolve icon path (lowercase to match install_assets)
        local icon_path="$ICON_DIR/$(echo "$icon_file" | tr '[:upper:]' '[:lower:]')"
        [[ -f "$icon_path" ]] || icon_path="google-chrome"

        local safe_name
        safe_name=$(echo "$name" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')

        if [[ "$url" == "google-chrome" ]]; then
            # Full browser shortcut
            cat > "$apps_dir/4youth-${safe_name}.desktop" << EOF
[Desktop Entry]
Version=1.0
Name=${name}
Comment=Open ${name}
Exec=/usr/bin/google-chrome-stable --password-store=basic --no-first-run --no-default-browser-check %U
Icon=${icon_path}
Terminal=false
Type=Application
Categories=Network;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=google-chrome
EOF
        else
            # Chrome --app shortcut for a website
            cat > "$apps_dir/4youth-${safe_name}.desktop" << EOF
[Desktop Entry]
Version=1.0
Name=${name}
Comment=Open ${name}
Exec=/usr/bin/google-chrome-stable --app=${url} --password-store=basic --no-first-run --no-default-browser-check
Icon=${icon_path}
Terminal=false
Type=Application
Categories=Network;
StartupWMClass=chrome-${safe_name}
EOF
        fi

        dock_ids+=("4youth-${safe_name}.desktop")
        log_info "Created shortcut: ${name}"
    done

    # Pin exactly these items to the dock (nothing else)
    local favorites_str
    favorites_str=$(printf "'%s', " "${dock_ids[@]}")
    favorites_str="[${favorites_str%, }]"

    gsettings set org.gnome.shell favorite-apps "$favorites_str" 2>/dev/null || true

    log_success "Desktop shortcuts created and pinned to dock"
}

# ============================================================
# 8. Lock Down the Desktop
# ============================================================
lockdown_desktop() {
    log_info "Locking down desktop environment..."

    # --- Hide all applications the user should not access ---

    local apps_dir="$HOME/.local/share/applications"
    mkdir -p "$apps_dir"

    # List of system .desktop files to hide from the user
    local hide_apps=(
        # Terminals (kept accessible for admin maintenance)
        # "org.gnome.Terminal.desktop"
        # "io.elementary.terminal.desktop"
        # "gnome-terminal.desktop"
        # File managers
        "org.gnome.Nautilus.desktop"
        "nautilus.desktop"
        # Settings
        "gnome-control-center.desktop"
        "org.gnome.Settings.desktop"
        # System tools
        "org.gnome.DiskUtility.desktop"
        "org.gnome.SystemMonitor.desktop"
        "gnome-system-monitor.desktop"
        "org.gnome.baobab.desktop"
        "org.gnome.Logs.desktop"
        "org.gnome.font-viewer.desktop"
        "org.gnome.Characters.desktop"
        "yelp.desktop"
        # Text editors
        "org.gnome.TextEditor.desktop"
        "org.gnome.gedit.desktop"
        "gedit.desktop"
        # Software center
        "org.gnome.Software.desktop"
        "snap-store_snap-store.desktop"
        "snap-store_ubuntu-software.desktop"
        # Other pre-installed apps
        "org.gnome.Calculator.desktop"
        "org.gnome.Calendar.desktop"
        "org.gnome.clocks.desktop"
        "org.gnome.Contacts.desktop"
        "org.gnome.Evince.desktop"
        "org.gnome.eog.desktop"
        "org.gnome.Totem.desktop"
        "org.gnome.Cheese.desktop"
        "org.gnome.Screenshot.desktop"
        "org.gnome.Weather.desktop"
        "org.gnome.Maps.desktop"
        "libreoffice-startcenter.desktop"
        "libreoffice-writer.desktop"
        "libreoffice-calc.desktop"
        "libreoffice-impress.desktop"
        "libreoffice-draw.desktop"
        "libreoffice-base.desktop"
        "libreoffice-math.desktop"
        "firefox.desktop"
        "firefox-esr.desktop"
        "thunderbird.desktop"
        "org.gnome.Rhythmbox3.desktop"
        "org.gnome.Shotwell.desktop"
        "transmission-gtk.desktop"
    )

    for app in "${hide_apps[@]}"; do
        local override_file="$apps_dir/$app"
        # Create a local override that hides the app from menus/search
        if [[ ! -f "$override_file" ]] || ! grep -q "NoDisplay=true" "$override_file" 2>/dev/null; then
            cat > "$override_file" << EOF
[Desktop Entry]
NoDisplay=true
Hidden=true
EOF
            log_info "Hidden: $app"
        fi
    done

    # --- Disable keyboard shortcuts that could bypass lockdown ---

    # Disable terminal shortcut and custom keybindings
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "[]" 2>/dev/null || true

    # Disable overview/activities (Super key) — prevents app search
    gsettings set org.gnome.mutter overlay-key '' 2>/dev/null || true

    # Disable switch-applications shortcut that shows app list
    gsettings set org.gnome.shell.keybindings toggle-application-view "[]" 2>/dev/null || true

    # Disable ability to open the run dialog
    gsettings set org.gnome.desktop.wm.keybindings panel-run-dialog "[]" 2>/dev/null || true

    # Set up a hidden admin terminal shortcut: Ctrl+Alt+F12
    # This gives admin access to a terminal for maintenance/unlocking
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
        "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/admin-terminal/']" 2>/dev/null || true
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/admin-terminal/ \
        name 'Admin Terminal' 2>/dev/null || true
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/admin-terminal/ \
        command '/usr/bin/gnome-terminal' 2>/dev/null || true
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/admin-terminal/ \
        binding '<Ctrl><Alt>F12' 2>/dev/null || true
    log_info "Admin terminal shortcut: Ctrl+Alt+F12"

    # Disable lock screen (they auto-login anyway, lock screen just confuses)
    gsettings set org.gnome.desktop.lockdown disable-lock-screen true 2>/dev/null || true

    # Disable user switching
    gsettings set org.gnome.desktop.lockdown disable-user-switching true 2>/dev/null || true

    # Don't disable log-out — GNOME 46 hides power off/restart when it's disabled.
    # Log out is harmless anyway since auto-login brings them straight back.

    # Allow shutdown/restart without admin password (JavaScript polkit format for Ubuntu 24.04+)
    sudo mkdir -p /etc/polkit-1/rules.d
    sudo tee /etc/polkit-1/rules.d/50-allow-power.rules > /dev/null << 'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.login1.power-off" ||
        action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
        action.id == "org.freedesktop.login1.reboot" ||
        action.id == "org.freedesktop.login1.reboot-multiple-sessions") {
        return polkit.Result.YES;
    }
});
EOF
    # Clean up old .pkla format if present
    sudo rm -f /etc/polkit-1/localauthority/50-local.d/50-allow-power.pkla 2>/dev/null || true
    log_info "Polkit: shutdown and restart allowed"

    # Disable print (optional — remove if printing is needed)
    gsettings set org.gnome.desktop.lockdown disable-printing false 2>/dev/null || true

    # --- Hide the dock "Show Applications" button ---
    gsettings set org.gnome.shell.extensions.dash-to-dock show-show-apps-button false 2>/dev/null || true
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true 2>/dev/null || true

    # --- Disable right-click on desktop ---
    gsettings set org.gnome.desktop.background show-desktop-icons false 2>/dev/null || true

    # --- Prevent access to GNOME Settings via dbus ---
    # Block the user from launching gnome-control-center even if they find a way
    local polkit_dir="/etc/polkit-1/localauthority/50-local.d"
    if [[ -d /etc/polkit-1 ]]; then
        sudo mkdir -p "$polkit_dir"
        sudo tee "$polkit_dir/50-restrict-settings.pkla" > /dev/null << 'EOF'
[Restrict System Settings]
Identity=unix-user:*
Action=org.gnome.controlcenter.*
ResultAny=no
ResultInactive=no
ResultActive=auth_admin
EOF
        log_info "Polkit: system settings require admin password"
    fi

    log_success "Desktop locked down"
}

# ============================================================
# 9. Disable Unnecessary Services
# ============================================================
disable_unnecessary_services() {
    log_info "Disabling unnecessary services..."

    # Disable Bluetooth if not needed
    sudo systemctl disable bluetooth.service 2>/dev/null || true
    sudo systemctl stop bluetooth.service 2>/dev/null || true

    log_success "Unnecessary services disabled"
}

# ============================================================
# 10. Set Wallpaper (clean branded desktop)
# ============================================================
set_wallpaper() {
    log_info "Setting desktop wallpaper..."

    local wallpaper_setting
    wallpaper_setting=$(jq -r '.wallpaper // "brand-colour"' "$CONFIG_FILE")

    if [[ "$wallpaper_setting" != "brand-colour" ]] && [[ -f "$WALLPAPER_DIR/wallpaper.png" ]]; then
        gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER_DIR/wallpaper.png" 2>/dev/null || true
        gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_DIR/wallpaper.png" 2>/dev/null || true
        gsettings set org.gnome.desktop.background picture-options 'zoom' 2>/dev/null || true
        log_success "Wallpaper set (custom image)"
    else
        gsettings set org.gnome.desktop.background picture-uri '' 2>/dev/null || true
        gsettings set org.gnome.desktop.background picture-uri-dark '' 2>/dev/null || true
        gsettings set org.gnome.desktop.background picture-options 'none' 2>/dev/null || true
        gsettings set org.gnome.desktop.background primary-color "$BRAND_COLOUR" 2>/dev/null || true
        gsettings set org.gnome.desktop.background color-shading-type 'solid' 2>/dev/null || true
        log_success "Wallpaper set (4Youth brand colour)"
    fi
}

# ============================================================
# 11. Display Team Message
# ============================================================
setup_team_message() {
    log_info "Setting up team message..."

    local message_url="https://popos.4youth.org.uk/message.php"
    local autostart_dir="$HOME/.config/autostart"
    local autostart_file="$autostart_dir/4youth-team-message.desktop"

    # Clean up old local HTML if it exists
    rm -f "$CONFIG_DIR/team-message.html"

    # Create autostart entry to show message on login (server-rendered, always current)
    # Use a cache-busting timestamp parameter so Chrome never shows a stale cached page
    mkdir -p "$autostart_dir"
    cat > "$autostart_file" << EOF
[Desktop Entry]
Type=Application
Name=4Youth Team Message
Exec=/usr/bin/google-chrome-stable --app=${message_url}?t=$(date +%s) --password-store=basic --no-first-run --no-default-browser-check --window-size=650,500
StartupWMClass=4youth-team-message
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

    log_success "Team message configured"
}

# ============================================================
# 12. Device Registration (boot tracking via SQLite API)
# ============================================================
register_device() {
    log_info "Registering device..."

    if ! command -v dmidecode &> /dev/null; then
        sudo apt install -y dmidecode
    fi

    local machine_id
    machine_id=$(cat /etc/machine-id 2>/dev/null || echo "unknown")

    if [[ "$machine_id" == "unknown" ]]; then
        log_warn "Could not read /etc/machine-id — skipping device registration"
        return
    fi

    # Gather hardware info
    local hostname_val cpu_model ram_gb disk_gb mac_addr serial_number os_version
    hostname_val=$(hostname 2>/dev/null || echo "unknown")
    cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //' || echo "unknown")
    ram_gb=$(awk '/MemTotal/ {printf "%.1f", $2/1048576}' /proc/meminfo 2>/dev/null || echo "0")
    local disk_bytes
    disk_bytes=$(lsblk -b -d -n -o SIZE /dev/sda 2>/dev/null || lsblk -b -d -n -o SIZE /dev/nvme0n1 2>/dev/null || echo "0")
    if [[ "$disk_bytes" =~ ^[0-9]+$ ]] && [[ "$disk_bytes" -gt 0 ]]; then
        disk_gb=$((disk_bytes / 1073741824))
    else
        disk_gb=0
    fi
    mac_addr=$(ip link show 2>/dev/null | awk '/ether/ {print $2; exit}' || echo "unknown")
    serial_number=$(sudo dmidecode -s system-serial-number 2>/dev/null || echo "unknown")
    os_version=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")

    # POST to device tracking API
    local api_response
    api_response=$(curl -sL -X POST "https://popos.4youth.org.uk/api.php?action=register" \
        -H "Content-Type: application/json" \
        -d "{
            \"secret\": \"4youth-kiosk-2026\",
            \"machine_id\": \"${machine_id}\",
            \"hostname\": \"${hostname_val}\",
            \"cpu\": \"${cpu_model}\",
            \"ram_gb\": ${ram_gb},
            \"disk_gb\": ${disk_gb},
            \"mac_address\": \"${mac_addr}\",
            \"serial\": \"${serial_number}\",
            \"os_version\": \"${os_version}\"
        }" 2>/dev/null || echo "")

    if echo "$api_response" | grep -q '"status":"ok"'; then
        log_success "Device registered: ${hostname_val} (${machine_id:0:8}...)"
    else
        log_warn "Device registration failed (network issue?) — will retry on next boot"
    fi
}

# ============================================================
# Update System (check, prompt, apply)
# ============================================================
check_for_updates() {
    log_info "Checking for script updates..."

    local local_hash remote_hash
    local remote_tmp="/tmp/pop-setup-remote.sh"

    local_hash=$(md5sum "$HOME/pop-setup.sh" 2>/dev/null | cut -d' ' -f1)

    curl -sL "$SCRIPT_URL" -o "$remote_tmp" 2>/dev/null
    if [[ ! -s "$remote_tmp" ]]; then
        log_warn "Could not fetch remote script (network issue?)"
        rm -f "$remote_tmp"
        return 1
    fi
    remote_hash=$(md5sum "$remote_tmp" | cut -d' ' -f1)
    rm -f "$remote_tmp"

    if [[ "$local_hash" != "$remote_hash" ]]; then
        if [[ -f "$SKIP_FILE" ]] && [[ "$(cat "$SKIP_FILE")" == "$remote_hash" ]]; then
            log_info "Update available but this version was skipped"
            return 1
        fi
        log_warn "Update available!"
        echo "  Local:  $local_hash"
        echo "  Remote: $remote_hash"
        return 0
    else
        log_success "Script is up to date"
        return 1
    fi
}

get_delay_count() {
    if [[ -f "$DELAY_FILE" ]]; then
        cat "$DELAY_FILE"
    else
        echo 0
    fi
}

increment_delay() {
    local current new
    current=$(get_delay_count)
    new=$((current + 1))
    echo "$new" > "$DELAY_FILE"
    echo "$new"
}

reset_delay() {
    rm -f "$DELAY_FILE"
    rm -f "$SKIP_FILE"
}

prompt_update() {
    # If running non-interactively (e.g. from systemd), auto-apply
    if [[ ! -t 0 ]]; then
        log_info "Non-interactive session — auto-applying update..."
        apply_update
        return
    fi

    local delays_remaining=$((MAX_DELAYS - $(get_delay_count)))

    echo ""
    log_warn "A new version of pop-setup.sh is available!"
    echo "  Delays used: $((MAX_DELAYS - delays_remaining)) / $MAX_DELAYS"
    echo ""

    if [[ $delays_remaining -le 0 ]]; then
        log_error "Maximum delays reached. Updating now."
        apply_update
        return
    fi

    echo "  [1] Update now (recommended)"
    echo "  [2] Delay ($delays_remaining remaining)"
    echo "  [3] Skip this version"
    echo ""
    read -p "Choose [1-3]: " -n 1 -r
    echo ""

    case $REPLY in
        1) apply_update ;;
        2)
            increment_delay > /dev/null
            log_info "Update delayed. $((delays_remaining - 1)) delay(s) remaining."
            ;;
        3)
            local skip_tmp="/tmp/pop-setup-skip.sh"
            curl -sL "$SCRIPT_URL" -o "$skip_tmp" 2>/dev/null
            if [[ -s "$skip_tmp" ]]; then
                md5sum "$skip_tmp" | cut -d' ' -f1 > "$SKIP_FILE"
            fi
            rm -f "$skip_tmp"
            reset_delay
            log_info "Version skipped."
            ;;
        *) log_info "No action taken." ;;
    esac
}

apply_update() {
    log_info "Downloading update..."

    backup_config "$HOME/pop-setup.sh"
    curl -sL "$SCRIPT_URL" -o "$HOME/pop-setup.sh.tmp"

    if [[ ! -s "$HOME/pop-setup.sh.tmp" ]]; then
        log_error "Download failed!"
        rm -f "$HOME/pop-setup.sh.tmp"
        return 1
    fi

    chmod +x "$HOME/pop-setup.sh.tmp"
    mv "$HOME/pop-setup.sh.tmp" "$HOME/pop-setup.sh"
    reset_delay

    log_success "Script updated!"

    log_info "Running updated script..."
    exec "$HOME/pop-setup.sh"
}

setup_login_check() {
    log_info "Setting up login update check..."

    mkdir -p "$HOME/.config/systemd/user"

    cat > "$HOME/.config/systemd/user/pop-setup-check.service" << EOF
[Unit]
Description=Check for pop-setup.sh updates on login
After=graphical-session.target
ConditionPathExists=$HOME/pop-setup.sh

[Service]
Type=oneshot
ExecStart=$HOME/pop-setup.sh --check-update
RemainAfterExit=no

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable pop-setup-check.service 2>/dev/null || \
        log_warn "Could not enable login check service"

    log_success "Login update check configured"
}

# ============================================================
# Usage
# ============================================================
usage() {
    cat << EOF
4Youth Ubuntu Kiosk Setup Script

Usage: $0 [OPTIONS]

Options:
  --check-update    Check for updates and prompt to install
  --apply-update    Download and apply update immediately
  --setup-login     Set up update check on login
  --reset-delay     Reset the delay counter
  --unlock          Remove lockdown (restore access to apps/settings)
  -h, --help        Show this help message

Without options, runs the full kiosk setup.
EOF
}

# ============================================================
# Unlock (for admin maintenance)
# ============================================================
unlock_desktop() {
    log_info "Removing desktop lockdown..."

    local apps_dir="$HOME/.local/share/applications"

    # Remove all our override .desktop files that hide apps
    for f in "$apps_dir"/*.desktop; do
        [[ -f "$f" ]] || continue
        # Only remove files we created (they contain NoDisplay=true and Hidden=true, nothing else)
        if grep -q "NoDisplay=true" "$f" 2>/dev/null && [[ $(wc -l < "$f") -le 4 ]]; then
            rm -f "$f"
            log_info "Restored: $(basename "$f")"
        fi
    done

    # Re-enable keyboard shortcuts
    gsettings reset org.gnome.mutter overlay-key 2>/dev/null || true
    gsettings reset org.gnome.shell.keybindings toggle-application-view 2>/dev/null || true
    gsettings reset org.gnome.desktop.wm.keybindings panel-run-dialog 2>/dev/null || true
    gsettings reset org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || true
    gsettings reset org.gnome.desktop.lockdown disable-lock-screen 2>/dev/null || true
    gsettings reset org.gnome.desktop.lockdown disable-user-switching 2>/dev/null || true
    gsettings reset org.gnome.desktop.lockdown disable-log-out 2>/dev/null || true

    # Re-enable show-apps button
    gsettings reset org.gnome.shell.extensions.dash-to-dock show-show-apps-button 2>/dev/null || true

    # Remove polkit restrictions
    sudo rm -f /etc/polkit-1/localauthority/50-local.d/50-restrict-settings.pkla 2>/dev/null || true
    sudo rm -f /etc/polkit-1/localauthority/50-local.d/50-allow-power.pkla 2>/dev/null || true
    sudo rm -f /etc/polkit-1/rules.d/50-allow-power.rules 2>/dev/null || true

    # Remove Chrome managed policies
    sudo rm -f /etc/opt/chrome/policies/managed/4youth-policy.json 2>/dev/null || true
    log_info "Removed Chrome managed policies"

    log_success "Desktop unlocked. Log out and back in for full effect."
}

# ============================================================
# Main
# ============================================================
main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check-update)
                check_not_root
                # Always refresh config, shortcuts, and team message on login
                download_config
                install_assets
                create_desktop_shortcuts
                set_wallpaper
                setup_team_message
                register_device
                # Then check for script updates
                check_for_updates && prompt_update
                exit 0
                ;;
            --apply-update)
                check_not_root
                apply_update
                exit $?
                ;;
            --setup-login)
                check_not_root
                setup_login_check
                exit 0
                ;;
            --reset-delay)
                reset_delay
                log_success "Delay counter reset"
                exit 0
                ;;
            --unlock)
                check_not_root
                unlock_desktop
                exit 0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    echo "========================================"
    echo "  4Youth Ubuntu Kiosk Setup"
    echo "  $(date)"
    echo "========================================"
    echo

    check_not_root
    check_ubuntu

    log_info "Starting kiosk setup..."
    echo

    install_prerequisites
    update_system
    install_chrome
    configure_chrome_policies
    configure_power
    configure_autologin
    download_config
    install_assets
    create_desktop_shortcuts
    lockdown_desktop
    disable_unnecessary_services
    set_wallpaper
    setup_team_message
    register_device
    setup_login_check

    echo
    log_success "Kiosk setup complete!"
    echo
    echo "The laptop will now:"
    echo "  - Auto-login on power on"
    echo "  - Show dock shortcuts configured in config.json"
    echo "  - Hide all other apps, settings, terminal, and file manager"
    echo "  - Prevent Chrome password saving and autofill"
    echo "  - Register device and track boots via Forgejo"
    echo ""
    echo "To temporarily unlock for admin maintenance:"
    echo "  ./pop-setup.sh --unlock"
    echo ""
    echo "Please reboot for all changes to take effect."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
