# Pop OS Setup Script

Reproducible laptop setup for Pop!_OS with automatic update checking.

## Quick Install

### New Laptop Setup

Run this single command on any new Pop OS laptop:

```bash
curl -sL https://raw.githubusercontent.com/JonHubbard1/pop-setup/main/pop-setup.sh -o ~/pop-setup.sh && chmod +x ~/pop-setup.sh && ./pop-setup.sh
```

Or download and run separately:

```bash
# Download the script
curl -sL https://raw.githubusercontent.com/JonHubbard1/pop-setup/main/pop-setup.sh -o ~/pop-setup.sh

# Make executable
chmod +x ~/pop-setup.sh

# Run setup
./pop-setup.sh
```

## Features

- **System Updates**: Full apt update/upgrade
- **Pop OS Tools**: system76-power, preload, TLP
- **Power Management**: Battery profile, CPU governor, GPU config
- **Desktop Apps**: Chrome (default browser), Discord, Slack, LibreOffice
- **Dev Tools**: Git, neovim, tmux, zsh, jq, ripgrep, fzf
- **Auto-login**: Password-free login with Chrome SSO auto-launch
- **Dock Icons**: Pinned shortcuts for Microsoft 365, Outlook, Teams, etc.
- **Auto-update**: Checks GitHub on each login (max 3 delays)

## Update Commands

| Command | Description |
|---------|-------------|
| `./pop-setup.sh` | Run full setup |
| `./pop-setup.sh --check-update` | Check and prompt for update |
| `./pop-setup.sh --apply-update` | Apply update immediately |
| `./pop-setup.sh --setup-login` | Configure login-time update check |
| `./pop-setup.sh --reset-delay` | Reset the delay counter |

## GitHub Repository

### Public vs Private

**Public Repository** (current setup):
- Anyone can view the code
- Laptops can fetch updates via HTTPS without authentication
- Updates work automatically

**Private Repository**:
- Code is private to your organization
- Requires authentication (SSH key or Personal Access Token)
- To use private repo, laptops need:
  1. SSH key added to GitHub account, OR
  2. Personal Access Token configured

To switch to private repo:
1. Create private repo on GitHub
2. Push code: `git remote set-url origin git@github.com:JonHubbard1/pop-setup.git && git push`
3. Update `GITHUB_REPO` in script
4. Ensure each laptop has SSH access

### Security Considerations

This script is **safe and auditable**:

- **No hidden commands**: All operations are visible in the script
- **No network callbacks**: Only fetches from your GitHub repo
- **No credentials stored**: Uses sudo prompts, doesn't store passwords
- **Backups created**: Existing configs are backed up before changes
- **Idempotent**: Safe to run multiple times
- **Reviewable**: Code is public for anyone to audit

**What the script does NOT do:**
- Phone home or beacon to external servers
- Store or transmit credentials
- Download code from untrusted sources
- Modify system files outside expected paths
- Disable security features

**To verify safety:**
```bash
# Review the script before running
cat ~/pop-setup.sh | less

# Or view on GitHub
https://github.com/JonHubbard1/pop-setup/main/pop-setup.sh
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
- **Auto-launch**: Change URL in `configure_autologin()`

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
- All operations are logged and reversible

## License

MIT
