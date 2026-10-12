# OpenCode Portable

Complete portable development environment for Windows. Run from USB without installation.

![Version](https://img.shields.io/badge/version-1.0-blue)
![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-lightgrey)
![Size](https://img.shields.io/badge/portable%20size-~6.8%20GB-orange)

> ### Also available for Linux
> This is the **Windows** edition. For the Linux version, with the same
> toolchain and the same portable design, see:
> **[opencode-portable-linux](https://github.com/palashsuryavanshi/opencode-portable-linux)**

## What's Included

| Tool | Version | Purpose |
|------|---------|---------|
| **OpenCode GUI + CLI** | v2.x | AI coding assistant with session persistence |
| **VS Code Portable** | Latest stable | Full editor, settings/extensions on stick |
| **Temurin JDK** | 21 LTS | Java development |
| **Android SDK** | cmdline-tools 16111833 | Android builds (adb, aapt2, apksigner, Gradle) |
| **Git for Windows** | 2.56 (PortableGit) | Version control + Git Bash (Unix-like shell) |
| **Node.js** | 24 LTS | JavaScript/TypeScript |
| **Go** | 1.27 | Go development |
| **Maven** | 3.9 | Java builds |
| **Python** | 3.13 | Python development |
| **.NET SDK** | 10 | C#/F# development |
| **Rust** | 1.99 (via rustup) | Rust development |

## Quick Start

1. **Download** the latest release zip from [Releases](https://github.com/palashsuryavanshi/opencode_portable/releases)
2. **Extract** to your USB drive (e.g., `E:\opencode-portable`)
3. **Run** `Launch.cmd`
4. **Choose an option:**
   - **1** — OpenCode GUI (sign in on first run)
   - **2** — VS Code
   - **3** — Developer Shell (all tools on PATH)
   - **4** — Git Bash
   - **7** — Session backup/restore/import
   - **8** — Verify portable setup
   - **9** — Update OpenCode

## First Run — Install the Tools You Want

The full bundle is about **5 GB installed**. You almost certainly do not need all
of it, so the installer lets you pick. Run this from the portable root:

```powershell
powershell -ExecutionPolicy Bypass -File build\install-selected-tools.ps1
```

You get a toggle list with the size of each toolchain and a running total:

```
  #   Tool                          Size  Notes
  1   OpenCode GUI + CLI            740 MB  The AI coding assistant (required)
  2   VS Code (portable)           1030 MB  Portable ZIP edition, data on the stick
  3   Temurin JDK 21 LTS            330 MB  Java, needed for Android and Gradle
  4   Android SDK                   655 MB  cmdline-tools, platform-tools, build-tools 34/35
  ...
```

Enter numbers to toggle, `a` for all, `n` for none. Before downloading it checks
free space on the USB, then fetches the selected items in parallel and verifies
each one afterwards. Already-installed tools are skipped.

### Non-interactive

```powershell
.\build\install-selected-tools.ps1 -Minimal                  # OpenCode only (~740 MB)
.\build\install-selected-tools.ps1 -Only "jdk,node,go"       # pick specific toolchains
.\build\install-selected-tools.ps1 -All                       # everything
.\build\install-selected-tools.ps1 -List                      # show the catalogue, install nothing
.\build\install-selected-tools.ps1 -Only "jdk" -Force         # reinstall even if present
.\build\install-selected-tools.ps1 -Only "android" -NoAndroid # cmdline-tools only, skip packages
```

OpenCode itself is always included. Choosing Android automatically pulls in the
JDK, because the SDK manager will not run without it.

| Flag | Meaning |
|---|---|
| *(none)* | interactive toggle list |
| `-All` | install everything, unattended |
| `-Minimal` | OpenCode only |
| `-Only "a,b,c"` | install exactly these toolchains |
| `-Force` | reinstall tools that are already present |
| `-List` | print the catalogue and exit |
| `-NoAndroid` | install Android cmdline-tools but skip the SDK packages |

### Installing everything the old way

The original three-stage scripts still work if you prefer them:

```powershell
PowerShell -ExecutionPolicy Bypass -File build\fetch-tools.ps1
PowerShell -ExecutionPolicy Bypass -File build\install-tools.ps1
PowerShell -ExecutionPolicy Bypass -File build\setup-android.ps1
```

## Features

- **100% portable** — all data stays on USB (sessions, config, caches, tool caches)
- **No admin required** — runs on any Windows 10/11 machine
- **Session persistence** — chat history follows the stick
- **Auto-updater** — option 9 downloads latest OpenCode from opencode.ai
- **Session backup/restore** — option 7 manages session snapshots
- **Path verification** — option 8 confirms isolation from host

## Updating OpenCode

From `Launch.cmd` choose **9**, or run directly:
```cmd
bin\Update-OpenCode.cmd
```
Flags: `-Force` (reinstall same version), `-NoBackup` (skip backup)

## Session Management

From `Launch.cmd` choose **7**:
- **Backup** — snapshot sessions to `data/backups/`
- **Restore** — load latest snapshot
- **Import** — pull sessions from host PC's OpenCode install
- **List** — show available backups

## Verification

From `Launch.cmd` choose **8** — confirms:
- All XDG paths point to USB
- Session database present
- All toolchains on PATH

## Directory Structure

```
opencode-portable/
├── Launch.cmd              # Main menu
├── bin/                    # All launchers
│   ├── OpenCode.cmd        # OpenCode GUI
│   ├── VSCode.cmd          # VS Code
│   ├── Shell.cmd           # Dev shell (cmd)
│   ├── Bash.cmd            # Git Bash
│   ├── OpenCodeCLI.cmd     # OpenCode TUI
│   ├── Android.cmd         # Android SDK manager
│   ├── Sync.cmd            # Session backup/restore
│   ├── Update-OpenCode.cmd # Updater wrapper
│   ├── Verify.cmd          # Path verification
│   └── env.cmd             # Environment setup (called by all)
├── apps/                   # Tools (populated by build scripts)
├── data/                   # All persistent data
│   ├── opencode-data/      # Sessions (SQLite DB)
│   ├── opencode-config/    # Config, auth, service.json
│   ├── opencode-cache/     # Logs, caches
│   ├── opencode-state/     # State files
│   ├── appdata/            # Redirected APPDATA/LOCALAPPDATA
│   ├── cargo/ rustup/      # Rust toolchains
│   ├── gopath/ gocache/    # Go caches
│   ├── gradle/             # Gradle cache
│   ├── npm-cache/ pip-cache/ # Package caches
│   ├── vscode-user/        # VS Code settings/extensions
│   └── backups/            # Session snapshots
├── projects/               # Your code goes here
├── build/                  # Build scripts
│   ├── install-selected-tools.ps1 # pick which toolchains to install (start here)
│   ├── fetch-tools.ps1     # Download tool installers
│   ├── install-tools.ps1   # Extract to apps/
│   └── setup-android.ps1   # Install Android SDK packages
├── docs/                   # Documentation (empty)
├── downloads/              # Downloaded installers (gitignored)
└── README.md               # This file
```

## How It Works

All launchers call `bin/env.cmd` which sets:
- `XDG_DATA_HOME` → `data/opencode-data`
- `XDG_CONFIG_HOME` → `data/opencode-config`
- `XDG_CACHE_HOME` → `data/opencode-cache`
- `XDG_STATE_HOME` → `data/opencode-state`
- `APPDATA` / `LOCALAPPDATA` → `data/appdata/`
- `USERPROFILE` / `HOME` → `data/home/`
- Tool caches → `data/<tool>-cache/`

This ensures **nothing writes to the host machine**.

## Requirements

- Windows 10/11 (64-bit)
- ~8 GB free space on USB for full toolchain
- Internet connection 

## Platforms

| Edition | Repository | Launcher |
|---|---|---|
| **Windows 10/11 (x64)** | [`opencode_portable`](https://github.com/palashsuryavanshi/opencode_portable) — *this repo* | `Launch.cmd` |
| **Linux (x64)** | [`opencode-portable-linux`](https://github.com/palashsuryavanshi/opencode-portable-linux) | `./launch.sh` |

Both editions ship the same toolchains, the same session layout, and the same
`data/`-on-the-stick isolation model. Session databases are not shared between
platforms, but the launchers and directory structure are identical, so moving
a workflow between the two is straightforward.

## License

Tools subject to their respective licenses. This packaging is MIT.
