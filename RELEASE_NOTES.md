# OpenCode Portable v1.0

Complete portable development environment for Windows. Run from USB without installation.

## What's Included (via build scripts)

- **OpenCode GUI + CLI** (v2.x) - AI coding assistant with session persistence
- **VS Code Portable** - Full editor with settings/extensions on the stick
- **Temurin JDK 21 LTS** - Java development
- **Android SDK** - cmdline-tools, platform-tools, build-tools 35/34, platforms 35/34
- **Git for Windows** (PortableGit) - Includes Git Bash (Unix-like shell)
- **Node.js 24 LTS** - JavaScript/TypeScript
- **Go 1.27** - Go development
- **Maven 3.9** - Java builds
- **Python 3.13** - Python development
- **.NET SDK 10** - C#/F# development
- **Rust** (rustup) - Rust development

## Quick Start

1. **Download** this release zip (or clone the repo)
2. **Extract** to your USB drive (e.g., `E:\opencode-portable`)
3. **Run** `Launch.cmd`
4. **Choose option 1** for OpenCode GUI, or **a** for the tool menu
   (VS Code, Developer Shell, Git Bash, Android SDK Manager)

## First Run - Install Tools

On first run, the tools need to be installed:

```cmd
# From the portable root (Launch.cmd menu doesn't have this yet, run manually):
PowerShell -ExecutionPolicy Bypass -File build\fetch-tools.ps1
PowerShell -ExecutionPolicy Bypass -File build\install-tools.ps1
PowerShell -ExecutionPolicy Bypass -File build\setup-android.ps1
```

This downloads ~2 GB of tools and installs them to `apps/`. Only needs to be done once.

## Features

- **All data stays on USB** - sessions, config, caches, tool caches
- **No admin required** - runs on any Windows 10/11
- **Session persistence** - chat history follows the stick
- **Auto-updater** - option 5 in Launch.cmd downloads latest OpenCode
- **Session backup/restore** - option 3 in Launch.cmd
- **Verification** - option 4 checks path isolation
- **Tool manager** - option a installs, removes and launches toolchains

## Updating OpenCode

From `Launch.cmd` choose **5** (Update OpenCode), or run:
```cmd
bin\Update-OpenCode.cmd
```

## Session Management

From `Launch.cmd` choose **3** (Sessions):
- **Backup** - snapshot current sessions
- **Restore** - load latest snapshot
- **Import** - pull sessions from host PC's OpenCode install

## Verification

From `Launch.cmd` choose **4** (Verify) - confirms all paths point to USB.

## Directory Structure

```
opencode-portable/
├── Launch.cmd              # Main menu
├── bin/                    # All launchers
├── apps/                   # Tools (populated by build scripts)
├── data/                   # All persistent data (sessions, caches, config)
├── projects/               # Your code goes here
├── build/                  # Build scripts
└── README.md               # This file
```

## Requirements

- Windows 10/11 (64-bit)
- ~8 GB free space on USB for full toolchain
- Internet connection for initial tool downloads

## License

Tools subject to their respective licenses. This packaging is MIT.