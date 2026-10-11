# OpenCode Portable

Complete portable development environment for Windows. Run from USB without installation.

![Version](https://img.shields.io/badge/version-1.0-blue)
![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-lightgrey)
![Size](https://img.shields.io/badge/portable%20size-~6.8%20GB-orange)

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

## First Run — Install Tools

The repository contains launchers and build scripts. Tools are downloaded on first use:

```cmd
# From the portable root directory:
PowerShell -ExecutionPolicy Bypass -File build\fetch-tools.ps1
PowerShell -ExecutionPolicy Bypass -File build\install-tools.ps1
PowerShell -ExecutionPolicy Bypass -File build\setup-android.ps1
```

This downloads ~2 GB and installs to `apps/`. Only needed once per USB.

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

## License

Tools subject to their respective licenses. This packaging is MIT.
