# OpenCode Portable - Clean Release

This is a **clean template** with no user data, sessions, or personal configuration.
All tools are pre-installed and ready to use.

## What's Included

- **OpenCode GUI + CLI** (v2.x) - in pps/opencode/
- **VS Code Portable** - in pps/vscode/
- **Java (Temurin 21 LTS)** - in pps/jdk/
- **Android SDK (cmdline-tools)** - in pps/android-sdk/
- **Git for Windows (PortableGit)** - in pps/git/
- **Node.js 24 LTS** - in pps/node/
- **Go 1.27** - in pps/go/
- **Maven 3.9** - in pps/maven/
- **Python 3.13** - in pps/python/
- **.NET SDK 10** - in pps/dotnet/
- **Rust (rustup)** - toolchains in data/rustup/, cargo home in data/cargo/

## Quick Start

1. Double-click **Launch.cmd**
2. Choose an option:
   - **1** - OpenCode GUI (sign in on first run)
   - **2** - VS Code
   - **3** - Developer Shell (all tools on PATH)
   - **4** - Git Bash
   - **7** - Session backup/restore
   - **8** - Verify portable setup

## First Run

- OpenCode will prompt you to sign in / configure providers
- VS Code extensions and settings stay in data/vscode-user/
- All your projects go in projects/
- Run Verify.cmd (option 8) on any new machine to confirm paths

## Updating Tools

Run the scripts in uild/:
- etch-tools.ps1 - download latest versions
- install-tools.ps1 - extract to pps/
- setup-android.ps1 - install Android SDK packages

## License

Tools are subject to their respective licenses. This packaging is for convenience.
