# Pop OS Setup Script

Reproducible laptop setup for Pop!_OS with automatic update checking.

## Features

- **System Updates**: Full apt update/upgrade
- **Pop OS Tools**: system76-power, preload, TLP
- **Power Management**: Battery profile, CPU governor, GPU config
- **Desktop Apps**: Chrome (default browser), Discord, Slack, LibreOffice
- **Dev Tools**: Git, neovim, tmux, zsh, jq, ripgrep, fzf
- **Auto-login**: Password-free login with Chrome SSO auto-launch
- **Dock Icons**: Pinned shortcuts for Microsoft 365, Outlook, Teams, etc.
- **Auto-update**: Checks GitHub on each login (max 3 delays)

## Quick Start

### First-time Setup

```bash
# Download and run
curl -sL https://raw.githubusercontent.com/yourusername/pop-setup/main/pop-setup.sh -o ~/pop-setup.sh
chmod +x ~/pop-setup.sh
./pop-setup.sh
```

### Enable Login Update Check

```bash
./pop-setup.sh --setup-login
```

This configures a systemd service that checks for updates on every login.

## Update Commands

| Command | Description |
|---------|-------------|
| `./pop-setup.sh` | Run full setup |
| `./pop-setup.sh --check-update` | Check and prompt for update |
| `./pop-setup.sh --apply-update` | Apply update immediately |
| `./pop-setup.sh --setup-login` | Configure login-time update check |
| `./pop-setup.sh --reset-delay` | Reset the delay counter |

## GitHub Hosting

1. Create a new repository on GitHub:
   ```
   Repository name: pop-setup
   Visibility: Public (or Private for org use)
   ```

2. Push the script:
   ```bash
   cd ~/pop-setup
   git init
   git add pop-setup.sh README.md
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/yourusername/pop-setup.git
   git push -u origin main
   ```

3. Update the `GITHUB_REPO` variable in `pop-setup.sh`:
   ```bash
   GITHUB_REPO="yourusername/pop-setup"
   ```

## Update Flow

When an update is available:

1. **Login** → Update check runs automatically
2. **Prompt** shows:
   - Option 1: Update now (downloads and re-runs)
   - Option 2: Delay (reminds next login, 3 max)
   - Option 3: Skip this version
3. **After 3 delays** → Update is forced

## Customization

Edit the script to customize:

- **Websites**: Modify the `websites` array in `configure_dock_icons()`
- **Apps**: Add packages to `install_desktop_apps()`
- **Power**: Adjust profiles in `configure_power()`
- **Auto-launch**: Change URL in `configure_autnologin()`

## Files Created

| Path | Purpose |
|------|---------|
| `~/pop-setup.sh` | Main script |
| `~/.pop-setup-backups/` | Config backups |
| `~/.pop-setup-delay-count` | Delay tracking |
| `~/.config/systemd/user/pop-setup-check.service` | Login update check |
| `~/.local/share/applications/chrome-*.desktop` | Dock shortcuts |

## Security Notes

- Auto-login requires **full disk encryption** (enable during Pop OS install)
- Script never runs as root (uses sudo for privileged operations)
- Backups created before modifying configs

## License

MIT
