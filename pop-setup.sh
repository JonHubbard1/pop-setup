#!/usr/bin/env bash
#
# Pop OS Setup Script
# Reproducible laptop setup for Pop!_OS
#
# Usage: ./pop-setup.sh
#
# This script:
# - Updates system packages
# - Installs desktop applications
# - Configures Pop OS power management, scheduler, and GPU settings
# - Backs up and applies dotfiles/configs
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# GitHub configuration - Update these to your repo
GITHUB_REPO="yourusername/pop-setup"
GITHUB_BRANCH="main"
SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/pop-setup.sh"

# Delay tracking
MAX_DELAYS=3
DELAY_FILE="$HOME/.pop-setup-delay-count"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run this script as root. Use sudo when needed."
        exit 1
    fi
}

# Check if running on Pop OS
check_pop_os() {
    if [[ ! -f /etc/pop-os/os-release ]]; then
        log_warn "This script is designed for Pop!_OS. Detected: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Create backup of existing config files
backup_config() {
    local file="$1"
    if [[ -e "$file" ]]; then
        local backup_dir="$HOME/.pop-setup-backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        local basename=$(basename "$file")
        cp -r "$file" "$backup_dir/$basename.bak"
        log_info "Backed up: $file -> $backup_dir/$basename.bak"
    fi
}

# Add a line to shell config if not present
add_to_shell_config() {
    local line="$1"
    local shell_config="$HOME/.bashrc"
    if ! grep -qF "$line" "$shell_config" 2>/dev/null; then
        echo "$line" >> "$shell_config"
        log_info "Added to .bashrc: $line"
    fi
}

#
# System Update
#
update_system() {
    log_info "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
    log_success "System updated"
}

#
# Install Pop OS specific tools
#
install_pop_tools() {
    log_info "Installing Pop OS specific tools..."

    # system76-power is pre-installed on Pop OS, but ensure it's available
    if command -v system76-power &> /dev/null; then
        log_success "system76-power available"
    else
        log_warn "system76-power not found - may need to install system76-power"
    fi

    # Install kernel scheduler utilities
    sudo apt install -y preload
    log_success "Preload installed"
}

#
# Configure Power Management
#
configure_power() {
    log_info "Configuring power management..."

    # Set default power profile to battery for laptops
    if command -v system76-power &> /dev/null; then
        sudo system76-power profile battery
        log_info "Default power profile set to battery mode"

        # Enable battery-bt (battery threshold) if available
        if sudo system76-power profile-battery-threshold --help &> /dev/null 2>&1; then
            sudo system76-power profile-battery-threshold 80
            log_info "Battery charge threshold set to 80%"
        fi
    fi

    # Configure TLP for additional power management (if not using system76-power exclusively)
    if ! command -v tlp &> /dev/null; then
        log_info "Installing TLP for advanced power management..."
        sudo apt install -y tlp tlp-rdw
        sudo tlp start
    fi

    log_success "Power management configured"
}

#
# Configure CPU Governor
#
configure_cpu() {
    log_info "Configuring CPU governor..."

    # Set powersave as default for better battery life
    if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
        echo "powersave" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
        log_info "CPU governor set to powersave"
    else
        log_warn "CPU frequency scaling not available"
    fi

    log_success "CPU governor configured"
}

#
# Configure GPU (for hybrid graphics systems)
#
configure_gpu() {
    log_info "Configuring GPU settings..."

    if command -v system76-power &> /dev/null; then
        # Detect if hybrid graphics is available
        if system76-power graphics --help &> /dev/null 2>&1; then
            current_gpu=$(system76-power graphics 2>/dev/null || echo "unknown")
            log_info "Current GPU mode: $current_gpu"

            # Default to integrated for battery life (user can change)
            log_info "Setting GPU to integrated mode (run 'system76-power graphics switch' to change)"
        fi
    fi

    # Install GPU utilities if needed
    if ! command -v glxinfo &> /dev/null; then
        sudo apt install -y mesa-utils
    fi

    log_success "GPU configuration complete"
}

#
# Install Desktop Applications
#
install_desktop_apps() {
    log_info "Installing desktop applications..."

    # Web Browser - Install Chrome and set as default
    if ! command -v google-chrome &> /dev/null; then
        log_info "Adding Chrome repository..."
        wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/chrome.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/chrome.list
        sudo apt update
        sudo apt install -y google-chrome-stable
        log_success "Google Chrome installed"
    else
        log_success "Google Chrome already installed"
    fi

    # Set Chrome as default browser
    if command -v google-chrome &> /dev/null; then
        # Set via xdg-settings (works across desktop environments)
        xdg-settings set default-web-browser google-chrome.desktop 2>/dev/null || true

        # Also set via gsettings for GNOME-based environments (Pop OS uses COSMIC/GNOME)
        gsettings set org.gnome.shell favored-apps '[' 'google-chrome.desktop' ']' 2>/dev/null || true

        # Set Chrome as handler for http/https schemes
        xdg-mime set google-chrome.desktop x-scheme-handler/http 2>/dev/null || true
        xdg-mime set google-chrome.desktop x-scheme-handler/https 2>/dev/null || true

        log_success "Google Chrome set as default browser"
    fi

    # Install Chrome extension support for Microsoft SSO
    log_info "Microsoft SSO extension info..."
    # The Microsoft Single Sign-On extension must be installed manually from Chrome Web Store
    # Extension ID: ppnbnpeolgpkdlgjckdndopbflcpplknm
    mkdir -p "$HOME/.pop-setup-backups"
    cat > "$HOME/.pop-setup-backups/chrome-sso-extension.txt" << 'EXTENSION_INFO'
After first Chrome launch, install the Microsoft Single Sign-On extension:

Chrome Web Store:
  https://chromewebstore.google.com/detail/microsoft-single-sign-on/ppnbnpeolgpkdlgjckdndopbflcpplknm

This extension enables SSO for Microsoft 365 / Azure AD / Entra ID.
EXTENSION_INFO
    log_success "SSO extension info saved to ~/.pop-setup-backups/chrome-sso-extension.txt"

    # Communication Apps
    sudo apt install -y discord slack

    # Productivity Tools
    sudo apt install -y \
        libreoffice \
        evince \
        gnome-calculator \
        gnome-calendar

    # Font installation
    sudo apt install -y \
        fonts-firacode \
        fonts-jetbrains-mono \
        fonts-noto \
        fonts-ubuntu

    log_success "Desktop applications installed"
}

#
# Setup Development Basics (optional but recommended)
#
install_dev_basics() {
    log_info "Installing basic development tools..."

    sudo apt install -y \
        git \
        curl \
        wget \
        jq \
        ripgrep \
        fzf \
        neovim \
        tmux \
        zsh \
        build-essential \
        libssl-dev \
        pkg-config \
        libdbus-1-dev \
        libglib2.0-dev

    log_success "Development basics installed"
}

#
# Configure Shell and Prompt
#
configure_shell() {
    log_info "Configuring shell..."

    # Set zsh as default shell
    if [[ ! $SHELL =~ zsh ]]; then
        chsh -s $(which zsh)
        log_info "Default shell changed to zsh"
    fi

    # Install oh-my-zsh if not present
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        log_info "Installing oh-my-zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

    log_success "Shell configured"
}

#
# Backup and Apply Configs
#
setup_configs() {
    log_info "Setting up configurations..."

    # Create config directory
    mkdir -p "$HOME/.config"

    # Backup existing configs
    backup_config "$HOME/.bashrc"
    backup_config "$HOME/.zshrc"
    backup_config "$HOME/.tmux.conf"
    backup_config "$HOME/.config/nvim"

    # Create basic .bashrc additions
    add_to_shell_config "# Pop OS Setup"
    add_to_shell_config "export EDITOR='nvim'"
    add_to_shell_config "export VISUAL='nvim'"
    add_to_shell_config "alias ll='ls -la'"
    add_to_shell_config "alias gs='git status'"
    add_to_shell_config "alias gp='git pull'"
    add_to_shell_config "alias gc='git commit'"

    # Source bashrc to apply changes
    source "$HOME/.bashrc" 2>/dev/null || true

    log_success "Configurations applied"
}

#
# Configure Auto-login and Chrome SSO Auto-launch
#
configure_autologin() {
    log_info "Configuring auto-login..."

    # Get current username
    local username="$USER"

    # Pop OS uses GDM (GNOME Display Manager)
    local gdm_custom_conf="/etc/gdm3/custom.conf"

    # Backup existing GDM config
    backup_config "$gdm_custom_conf"

    # Enable auto-login in GDM
    if [[ -f "$gdm_custom_conf" ]]; then
        # Remove any existing AutomaticLogin line
        sudo sed -i '/^AutomaticLogin/d' "$gdm_custom_conf"
        # Add auto-login for current user
        echo "AutomaticLogin = $username" | sudo tee -a "$gdm_custom_conf"
        log_success "Auto-login enabled for user: $username"
    else
        log_warn "GDM config not found at $gdm_custom_conf"
    fi

    # Configure Chrome to auto-launch with Microsoft SSO page on login
    log_info "Configuring Chrome auto-launch on login..."

    # Create systemd user directory if not exists
    mkdir -p "$HOME/.config/systemd/user"

    # Create a service file to launch Chrome on login
    cat > "$HOME/.config/systemd/user/chrome-sso.service" << EOF
[Unit]
Description=Launch Chrome to Microsoft SSO
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=/usr/bin/google-chrome-stable --no-first-run --no-default-browser-check https://login.microsoftonline.com
Restart=on-failure

[Install]
WantedBy=default.target
EOF

    # Enable the service
    systemctl --user daemon-reload
    systemctl --user enable chrome-sso.service 2>/dev/null || log_warn "Could not enable chrome-sso service (may require reboot)"

    # Also add to GNOME autostart for compatibility
    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/chrome-sso.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Chrome Microsoft SSO
Exec=/usr/bin/google-chrome-stable --no-first-run --no-default-browser-check https://login.microsoftonline.com
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

    log_success "Auto-login and Chrome SSO auto-launch configured"
    log_warn "Auto-login means anyone with physical access can log in. Ensure disk encryption is enabled."
}

#
# Configure Dock Icons with Website Shortcuts
#
configure_dock_icons() {
    log_info "Configuring dock icons with website shortcuts..."

    # Create directory for custom applications
    mkdir -p "$HOME/.local/share/applications"

    # Define websites to pin to dock
    declare -A websites=(
        ["microsoft-365"]="https://www.office.com"
        ["outlook"]="https://outlook.office.com"
        ["teams"]="https://teams.microsoft.com"
        ["sharepoint"]="https://login.microsoftonline.com"
        ["lamplight"]="https://lamplight.online"
        ["easyyouthclub"]="https://4youth.org.uk"
    )

    # Create Chrome app shortcuts for each website
    for name in "${!websites[@]}"; do
        url="${websites[$name]}"
        local app_name="Chrome ${name}"
        local desktop_file="$HOME/.local/share/applications/chrome-${name}.desktop"

        # Create Chrome app mode shortcut (opens in its own window without browser UI)
        cat > "$desktop_file" << EOF
[Desktop Entry]
Version=1.0
Name=${app_name}
Comment=Open ${name} in Chrome
Exec=/usr/bin/google-chrome-stable --app=${url} --no-first-run --no-default-browser-check
Icon=google-chrome
Terminal=false
Type=Application
Categories=Network;Application;
StartupWMClass=chrome-${name}
EOF

        log_info "Created shortcut: ${app_name} -> ${url}"
    done

    # Pin the shortcuts to the dock (favorites)
    # Get current favorites
    current_favorites=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || echo "[]")

    # Build new favorites list with our Chrome shortcuts
    # Note: We need to include the .desktop filenames without path
    new_favorites=('chrome-microsoft-365.desktop' 'chrome-outlook.desktop' 'chrome-teams.desktop' 'chrome-sharepoint.desktop')

    # Add some default apps if they exist
    [[ -f /usr/share/applications/org.gnome.Nautilus.desktop ]] && new_favorites+=('org.gnome.Nautilus.desktop')
    [[ -f /usr/share/applications/org.gnome.Terminal.desktop ]] && new_favorites+=('org.gnome.Terminal.desktop')

    # Set the favorites
    gsettings set org.gnome.shell favorite-apps "$(printf '%s\n' "${new_favorites[@]}" | jq -R . | jq -s .)" 2>/dev/null || \
        log_warn "Could not set dock favorites (GNOME settings may not be available)"

    log_success "Dock icons configured with website shortcuts"
}

#
# Check for Script Updates from GitHub
#
check_for_updates() {
    log_info "Checking for script updates from GitHub..."

    # Get hash of current local script (excluding the config lines at top)
    local_hash=$(tail -n +20 "$HOME/pop-setup.sh" 2>/dev/null | md5sum | cut -d' ' -f1)

    # Get hash of remote script
    remote_content=$(curl -sL "$SCRIPT_URL" 2>/dev/null || echo "")
    if [[ -z "$remote_content" ]]; then
        log_warn "Could not fetch remote script (network issue?)"
        return 1
    fi
    remote_hash=$(echo "$remote_content" | tail -n +20 | md5sum | cut -d' ' -f1)

    if [[ "$local_hash" != "$remote_hash" ]]; then
        log_warn "Update available!"
        echo ""
        echo "  Local version hash:  $local_hash"
        echo "  Remote version hash: $remote_hash"
        echo ""
        return 0  # Update available
    else
        log_success "Script is up to date"
        return 1  # No update needed
    fi
}

#
# Get current delay count
#
get_delay_count() {
    if [[ -f "$DELAY_FILE" ]]; then
        cat "$DELAY_FILE"
    else
        echo 0
    fi
}

#
# Increment delay count
#
increment_delay() {
    local current=$(get_delay_count)
    local new=$((current + 1))
    echo "$new" > "$DELAY_FILE"
    echo "$new"
}

#
# Reset delay count (after update is applied)
#
reset_delay() {
    rm -f "$DELAY_FILE"
}

#
# Prompt user to update or delay
#
prompt_update() {
    local delays_remaining=$((MAX_DELAYS - $(get_delay_count)))

    echo ""
    log_warn "A new version of pop-setup.sh is available!"
    echo ""
    echo "  You have delayed $((MAX_DELAYS - delays_remaining)) time(s) already."
    echo "  Delays remaining: $delays_remaining"
    echo ""

    if [[ $delays_remaining -le 0 ]]; then
        log_error "Maximum delays ($MAX_DELAYS) reached. Update will be applied now."
        apply_update
        return
    fi

    echo "Options:"
    echo "  [1] Update now (recommended)"
    echo "  [2] Delay update (reminds you next login, $delays_remaining left)"
    echo "  [3] Skip this version (won't remind again)"
    echo ""

    read -p "Choose option [1-3]: " -n 1 -r
    echo ""

    case $REPLY in
        1)
            apply_update
            ;;
        2)
            increment_delay > /dev/null
            log_info "Update delayed. You have $((delays_remaining - 1)) delay(s) remaining."
            ;;
        3)
            # Mark this version as skipped
            echo "$(get_delay_count)" > "$DELAY_FILE"
            echo "skipped:$(date +%Y%m%d_%H%M%S)" >> "$DELAY_FILE"
            log_info "Update skipped. Will check again on next version."
            ;;
        *)
            log_info "No action taken."
            ;;
    esac
}

#
# Apply update from GitHub
#
apply_update() {
    log_info "Downloading update from GitHub..."

    # Backup current script
    backup_config "$HOME/pop-setup.sh"

    # Download new version
    curl -sL "$SCRIPT_URL" -o "$HOME/pop-setup.sh.tmp"

    # Verify download succeeded
    if [[ ! -s "$HOME/pop-setup.sh.tmp" ]]; then
        log_error "Download failed!"
        rm -f "$HOME/pop-setup.sh.tmp"
        return 1
    fi

    # Make executable and replace
    chmod +x "$HOME/pop-setup.sh.tmp"
    mv "$HOME/pop-setup.sh.tmp" "$HOME/pop-setup.sh"

    # Reset delay counter
    reset_delay

    log_success "Script updated successfully!"

    # Re-execute the new script
    log_info "Running updated script..."
    exec "$HOME/pop-setup.sh" "$@"
}

#
# Setup Login Check Service (runs on every login)
#
setup_login_check() {
    log_info "Setting up update check on login..."

    # Create systemd user directory
    mkdir -p "$HOME/.config/systemd/user"

    # Create the login check script
    cat > "$HOME/.config/systemd/user/pop-setup-check.sh" << CHECKSCRIPT
#!/usr/bin/env bash
# Pop Setup Login Update Check

DELAY_FILE="$HOME/.pop-setup-delay-count"
SCRIPT_PATH="$HOME/pop-setup.sh"
SCRIPT_URL="$SCRIPT_URL"

# Check if script exists
if [[ ! -f "$SCRIPT_PATH" ]]; then
    exit 0
fi

# Source the script to get functions
source "$SCRIPT_PATH" 2>/dev/null || exit 0

# Check for updates
if check_for_updates 2>/dev/null; then
    # Update available, prompt user
    prompt_update
fi
CHECKSCRIPT

    chmod +x "$HOME/.config/systemd/user/pop-setup-check.sh"

    # Create systemd service
    cat > "$HOME/.config/systemd/user/pop-setup-check.service" << EOF
[Unit]
Description=Check for pop-setup.sh updates on login
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=$HOME/.config/systemd/user/pop-setup-check.sh
RemainAfterExit=no

[Install]
WantedBy=default.target
EOF

    # Enable the service
    systemctl --user daemon-reload
    systemctl --user enable pop-setup-check.service 2>/dev/null || \
        log_warn "Could not enable login check service (may require reboot)"

    log_success "Login update check configured"
}

#
# Show usage
#
usage() {
    cat << EOF
Pop OS Setup Script - Reproducible laptop setup

Usage: $0 [OPTIONS]

Options:
  --check-update    Check for updates and prompt to install
  --apply-update    Download and apply update immediately
  --setup-login     Set up update check on login (run once)
  --reset-delay     Reset the delay counter
  --force           Run full setup without prompts
  -h, --help        Show this help message

Without options, runs the full setup interactively.
EOF
}

#
# Main Execution
#
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check-update)
                check_root
                if check_for_updates; then
                    prompt_update
                fi
                exit 0
                ;;
            --apply-update)
                check_root
                apply_update
                exit $?
                ;;
            --setup-login)
                check_root
                setup_login_check
                exit 0
                ;;
            --reset-delay)
                reset_delay
                log_success "Delay counter reset"
                exit 0
                ;;
            --force)
                SKIP_PROMPTS=true
                shift
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
    echo "  Pop OS Setup Script"
    echo "  $(date)"
    echo "========================================"
    echo

    check_root
    check_pop_os

    log_info "Starting setup..."
    echo

    update_system
    install_pop_tools
    configure_power
    configure_cpu
    configure_gpu
    install_desktop_apps
    install_dev_basics
    configure_shell
    setup_configs
    configure_autologin
    configure_dock_icons
    setup_login_check
    cleanup

    echo
    log_success "Setup complete!"
    echo
    echo "Please reboot for all changes to take effect."
    echo "Some configs may require logging out and back in."
    echo ""
    log_info "Update check configured to run on each login."
}

# Run main function
main "$@"
