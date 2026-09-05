# LARBS-inspired Windows desktop

A keyboard-first Windows 11 desktop built around GlazeWM, Zebar, Windows
Terminal, PowerShell, and Yazi. The profile keeps its runtime under
`%LOCALAPPDATA%\larbs-windows`, so the repository can be moved or updated
without breaking startup or shortcuts.

## What it configures

- GlazeWM workspaces, tiling behavior, launchers, and resilient logon startup.
- A minimal Zebar top bar with workspaces, active windows, wireless state,
  sound, battery, local date/time, and UTC time.
- Yazi openers for TeXstudio, MarkText, and Neovim, plus terminal integration.
- A small vi-mode PowerShell profile.
- A browser-based shortcut guide on `Alt+g`.

Machine-specific paths, private URLs, VPN profile IDs, and SSID fallbacks live
only in `settings.local.psd1`. That file is ignored by Git.

## Quick start

Windows 11 and [WinGet](https://learn.microsoft.com/windows/package-manager/winget/)
are recommended.

```powershell
git clone <your-repository-url> windows-larbs
cd windows-larbs
Copy-Item .\settings.example.psd1 .\settings.local.psd1
notepad .\settings.local.psd1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallPackages
```

Add `-InstallOptionalApps` to install the applications used by the engineering
shortcuts. The installer is idempotent: rerun it after pulling updates or
editing the source configuration.

The current live configuration is backed up before every install under:

```text
%LOCALAPPDATA%\larbs-windows-backups
```

## Installer options

| Option | Effect |
| --- | --- |
| `-InstallPackages` | Installs the core WM, bar, terminal, font, browser, Yazi with its preview/search tools, and Codex packages with WinGet. |
| `-InstallOptionalApps` | Installs TeXstudio, Wireshark, OBS, Neovim, KiCad, Bambu Studio, QGIS, Google Earth Pro, and MarkText. |
| `-SkipWindowsTerminal` | Leaves Windows Terminal settings unchanged. |
| `-SkipReload` | Deploys files without reloading or starting GlazeWM and Zebar. |
| `-RuntimeOnly` | Renders only the portable runtime; useful for CI and testing. |
| `-SettingsPath <path>` | Uses another PowerShell data file instead of `settings.local.psd1`. |
| `-InstallRoot <path>` | Overrides the stable runtime directory. |

Windows Terminal configuration is enabled by default. The legacy
`-ConfigureWindowsTerminal` switch remains accepted for existing commands.

## Local settings

Start from `settings.example.psd1`. Common customizations are:

- `Accent`: active-window border and top-bar colors.
- `Workspaces`: labels for workspaces 1 and 2.
- `DefaultProjectDirectory`: fallback directory for `Alt+e`.
- `Urls`: project management, source control, Onshape, and task pages.
- `Vpn.ProfileId`: OpenVPN Connect shortcut profile; MFA is still entered by hand.
- `Wifi.PreferredSsidFallbacks`: optional fallback when Windows hides the SSID.
- `Apps`: executable or shortcut overrides when automatic discovery is insufficient.
- `Codex.VimiumLauncher`: optional companion launcher for Codex keyboard controls.

Never force-add `settings.local.psd1` to a public repository.

## Main shortcuts

| Shortcut | Action |
| --- | --- |
| `Alt+1..9` | Focus workspace |
| `Alt+Shift+1..9` | Move the focused window and follow it |
| `Alt+h/l` | Focus left/right |
| `Alt+j` | Cycle windows in the current workspace |
| `Alt+Shift+h/j/k/l` | Move the focused window |
| `Alt+r` | Enter resize mode |
| `Alt+q` | Close the focused window |
| `Alt+Enter` | Windows Terminal |
| `Alt+c` | New Codex window in the current workspace |
| `Alt+v` | Claude Code |
| `Alt+e` | Yazi in the active Codex project directory |
| `Alt+g` | Full shortcut guide |

The full launcher list is maintained in
`glazewm/glazewm-shortcuts.html` and opens with `Alt+g`.

### ChatGPT windows across workspaces

`Alt+c` reuses a window from the main ChatGPT instance in the current workspace,
or invokes the app's native New Window command and moves the result there.
All new windows belong to the same app process and share its live sidebar state.
The launcher discovers the installed app dynamically after updates.

The first use adds `Ctrl+Shift+F12` for `newWindow` to the app's `keybindings.json`,
backing up that file and preserving unrelated shortcuts. A conflicting shortcut
is reported instead of replaced. Restart ChatGPT after saving work if the app
does not pick up the binding immediately. No app bundle changes are required.

Older launchers created separate profiles under
`%LOCALAPPDATA%\larbs-windows-state\codex-instances`. Finish work in those old
windows, close them normally, and use `Alt+c` to replace them with shared windows.
The launcher does not terminate old instances or delete their profile data.
Until they are closed, those older instances can still have stale sidebar state.

Run `powershell.exe -NoProfile -File .\tests\test-codex-native-window.ps1` for
the keymap-preservation and nested-workspace regression checks.

## Updating and checking

```powershell
git pull
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-desktop-profile.ps1
```

Source-only validation, also used by GitHub Actions:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-desktop-profile.ps1 -SourceOnly
```

Startup logs are written to `%LOCALAPPDATA%\glzr-startup`. Launcher errors are
written to `%LOCALAPPDATA%\larbs-windows\logs`.

## Layout

```text
glazewm/       WM config, launchers, startup recovery, and shortcut guide
zebar/         top-bar pack and local wireless-status worker
yazi/          file-manager config, openers, and terminal profile
powershell/    shell profile
lib/           shared settings and application discovery
settings.*     public template and ignored local overrides
```

The installer renders source templates into the stable runtime, then copies the
live GlazeWM, Zebar, and Yazi files into their normal application directories.

## Uninstall

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall-desktop-profile.ps1
```

Existing backups are not deleted. Use `-KeepRuntime` or `-KeepLiveConfigs` for
a partial removal.

## Publishing

Review the source-only test before the first push:

```powershell
git init
git add .
git status
git commit -m "Add Windows desktop profile"
```

Choose a license before making the repository public. The local settings file
should not appear in `git status`.
