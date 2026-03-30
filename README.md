# 4Youth Pop!_OS Kiosk Setup

Locks down a Pop!_OS laptop so users can only access Chrome and approved websites. Designed for 4Youth shared laptops.

## Quick Install

Run on a fresh Pop!_OS laptop:

```bash
curl -sL https://git.technoliga.co.uk/jon/pop-setup/raw/branch/main/pop-setup.sh -o ~/pop-setup.sh && chmod +x ~/pop-setup.sh && ./pop-setup.sh
```

## What It Does

- **Auto-login**: Powers on straight to the desktop, no password prompt
- **5 dock icons only**:
  - Chrome (full browser)
  - Lamplight (https://lamplight.online)
  - 4Youth Website (https://4youth.org.uk)
  - Microsoft Office 365 (https://www.office.com)
  - Microsoft Outlook (https://outlook.office365.com)
- **Everything else hidden**: terminal, file manager, settings, software centre, text editors, all other apps
- **Keyboard shortcuts disabled**: no Super key overview, no Alt+F2 run dialog, no Ctrl+Alt+T terminal
- **Power management**: battery profile, TLP for laptop battery life
- **Auto-update**: checks for script updates on each login

## Commands

| Command | Description |
|---------|-------------|
| `./pop-setup.sh` | Run full kiosk setup |
| `./pop-setup.sh --unlock` | Remove lockdown for admin maintenance |
| `./pop-setup.sh --check-update` | Check and prompt for update |
| `./pop-setup.sh --apply-update` | Apply update immediately |
| `./pop-setup.sh --setup-login` | Configure login-time update check |
| `./pop-setup.sh --reset-delay` | Reset the delay counter |

## Admin Maintenance

To temporarily unlock a laptop for admin work:

```bash
./pop-setup.sh --unlock
```

This restores access to terminal, settings, file manager, etc. Run the full setup again afterwards to re-lock:

```bash
./pop-setup.sh
```

## Update Flow

1. On login, the script checks for a newer version from Gitea
2. If an update is available, the user is prompted:
   - Update now (recommended)
   - Delay (max 3 times, then forced)
   - Skip this version
3. Updates download and re-run the setup automatically

## Files Created

| Path | Purpose |
|------|---------|
| `~/pop-setup.sh` | Main script |
| `~/.pop-setup-backups/` | Config backups |
| `~/.pop-setup-delay-count` | Update delay tracking |
| `~/.pop-setup-skipped-version` | Skipped version hash |
| `~/.config/systemd/user/pop-setup-check.service` | Login update check |
| `~/.local/share/applications/4youth-*.desktop` | Website shortcuts |

## Security Notes

- **Enable full disk encryption** during Pop!_OS install (auto-login means physical access = logged in)
- Script never runs as root (uses sudo for privileged operations)
- Configs are backed up before modification
- All operations are visible and auditable in the script
- Only fetches updates from your Gitea instance

## Repository

Hosted at `git.technoliga.co.uk/jon/pop-setup`.

## License

MIT
