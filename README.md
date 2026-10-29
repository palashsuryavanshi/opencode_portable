# OpenCode Portable — Windows

A complete development environment that runs from a USB stick. Nothing is
installed, no administrator rights are needed, and all of your data — chat
sessions, settings, caches — stays on the drive.

> **Linux user?** See [opencode-portable-linux](https://github.com/palashsuryavanshi/opencode-portable-linux) — same tools, same layout, same launcher design.

![Release](https://img.shields.io/badge/release-v1.1-blue)
![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11%20x64-lightgrey)
![Tools](https://img.shields.io/badge/tools-optional-installer-orange)

---

## Quick start

**1. Get the portable folder** onto your USB drive — clone it, or download and
extract the release zip:

```powershell
git clone https://github.com/palashsuryavanshi/opencode_portable.git E:\opencode-portable
```

> The repository is the **scaffold** — launchers, scripts and an empty directory
> structure. The toolchains themselves are ~5 GB and are downloaded by the
> installer in step 2, so that nobody has to take 5 GB they do not need.

**2. Install the tools you want:**

```powershell
cd E:\opencode-portable
powershell -ExecutionPolicy Bypass -File build\install-selected-tools.ps1
```

Pick what you need from the list. OpenCode on its own is about 740 MB.

**3. Launch:**

```
Launch.cmd
```

---

## The tool catalogue

| Tool | Size | Purpose |
|---|---:|---|
| **OpenCode GUI + CLI** | 740 MB | AI coding assistant, with chat history that follows the stick |
| **VS Code (portable)** | 1030 MB | Full editor; settings and extensions live on the drive |
| **Temurin JDK 21 LTS** | 330 MB | Java, and required by Android and Gradle |
| **Android SDK** | 655 MB | `adb`, `aapt2`, `d8`, `apksigner`, build-tools 34/35, platforms 34/35 |
| **Node.js** | 105 MB | JavaScript / TypeScript |
| **Go** | 240 MB | Go toolchain |
| **Python** | 250 MB | Full stdlib with `pip` |
| **.NET SDK** | 770 MB | C# and F# |
| **Rust** | 760 MB | `cargo` / `rustc` via `rustup` |
| **Git for Windows** | 390 MB | PortableGit, and a Git Bash shell |
| **Maven** | 12 MB | Java build tool |
| | **5282 MB** | full bundle |

Versions are resolved to the **current stable release** at install time, so you
are never pinned to an old build. Re-running the installer refreshes a tool.

### Installing

```powershell
.\build\install-selected-tools.ps1                      # interactive toggle list
.\build\install-selected-tools.ps1 -Minimal              # OpenCode only  (~740 MB)
.\build\install-selected-tools.ps1 -Only "jdk,node,go"   # exactly these
.\build\install-selected-tools.ps1 -All                  # everything
.\build\install-selected-tools.ps1 -List                 # show the catalogue, install nothing
.\build\install-selected-tools.ps1 -Only "jdk" -Force    # reinstall even if present
.\build\install-selected-tools.ps1 -Only "android" -NoAndroid   # cmdline-tools, no SDK packages
```

The installer lists every tool with its size, shows a running total, checks free
space on the drive before downloading, fetches your selection in parallel, and
**verifies each tool after installing**. Anything already installed is skipped.

### Managing installed tools

`Launch.cmd` → **10** opens the add/remove menu (`bin\Manage-Tools.cmd`):

| Action | Command |
|---|---|
| Interactive menu | `bin\Manage-Tools.cmd` |
| Show what is installed and how much space it uses | `bin\Manage-Tools.cmd -List` |
| Install tools | `bin\Manage-Tools.cmd -Add "python,go"` |
| Remove tools | `bin\Manage-Tools.cmd -Remove "vscode,dotnet"` |
| Delete cached installers | `bin\Manage-Tools.cmd -ClearDownloads` |

Removing a tool deletes only its folder under `apps\`. `data\` (chat sessions,
settings, caches) and `projects\` are never touched, so you can remove a tool
today and reinstall it later without losing work. OpenCode itself cannot be
removed from the menu - use **9** to reinstall or update it. If a tool is
running, the manager refuses to delete it; close it first, or pass `-Force`.

Some useful combinations:

| Goal | Selection | Size |
|---|---|---:|
| Just OpenCode | `-Minimal` | 740 MB |
| OpenCode + web dev | `-Only "vscode,node,git"` | 2265 MB |
| Android development | `-Only "android,jdk,node,vscode"` | 2860 MB |
| Full stack | `-All` | 5282 MB |

OpenCode itself is always included. Choosing Android automatically adds the JDK,
because the Android SDK manager will not run without it.

---

## The launcher menu

Double-click **`Launch.cmd`**.

| Key | Action |
|---|---|
| **1** | OpenCode GUI — main app, your sessions included |
| **2** | VS Code |
| **3** | Developer Shell — cmd with every toolchain on `PATH` |
| **4** | Git Bash |
| **5** | OpenCode CLI (TUI) — same sessions as the GUI |
| **6** | Android SDK Manager |
| **7** | Sessions — backup / restore / list / import |
| **8** | Verify portable setup |
| **9** | Update OpenCode |
| **10** | Manage tools - add / remove toolchains, clear cached installers |
| **0** | Exit |

---

## How the portability works

Every launcher calls `bin\env.cmd` first, which redirects each variable at the
drive. Nothing is written to the host machine:

| Variable | Redirected to |
|---|---|
| `XDG_DATA_HOME` | `data/opencode-data/` — sessions (SQLite database) |
| `XDG_CONFIG_HOME` | `data/opencode-config/` — settings, providers, auth |
| `XDG_CACHE_HOME` | `data/opencode-cache/` |
| `XDG_STATE_HOME` | `data/opencode-state/` |
| `APPDATA`, `LOCALAPPDATA` | `data/appdata/` |
| `USERPROFILE`, `HOME` | `data/home/` |
| `TEMP`, `TMP` | `data/tmp/` |
| `npm_config_cache`, `PIP_CACHE_DIR`, `GRADLE_USER_HOME`, `GOPATH`, `GOCACHE`, `CARGO_HOME`, `RUSTUP_HOME` | `data/…` |

Because `PATH` is rebuilt at every launch, tools you install later are picked up
automatically — there is nothing to edit.

> **Use the launchers, not the binaries.** Running `OpenCode.exe` or
> `opencode-cli.exe` directly from Explorer skips `env.cmd`, so OpenCode falls
> back to your real profile and creates an empty second set of sessions. Always
> go through `Launch.cmd`.

---

## Sessions

Your chat history is a SQLite database in `data/opencode-data\opencode\`. It
travels with the drive.

`Launch.cmd` → **7** gives you:

- **backup** — snapshot the current sessions into `data\backups\`
- **restore** — load the newest snapshot back
- **list** — show available snapshots
- **import** — pull sessions from a host PC's own OpenCode installation
  (`~\.local\share\opencode`)

Close OpenCode before backing up or restoring. The database runs in WAL mode, and
copying it while OpenCode is writing can produce a torn copy.

---

## Updating

```powershell
bin\Update-OpenCode.cmd          # or Launch.cmd -> 9
```

Downloads the latest stable OpenCode from
[opencode.ai](https://opencode.ai/download/stable/windows-x64-nsis), backs up
the current copy into `data\backups\`, and leaves all user data untouched.

Other tools update by re-running the installer with `-Force`.

---

## Directory layout

```
opencode-portable/
├── Launch.cmd                  main menu
├── bin/                        launchers
│   ├── OpenCode.cmd            OpenCode GUI
│   ├── VSCode.cmd              VS Code
│   ├── Shell.cmd               developer shell
│   ├── Bash.cmd                Git Bash
│   ├── OpenCodeCLI.cmd         OpenCode TUI
│   ├── Android.cmd             Android SDK manager
│   ├── Sync.cmd                session backup / restore
│   ├── Update-OpenCode.cmd     OpenCode updater
│   ├── Verify.cmd              path isolation check
│   └── env.cmd                 sets every path to the stick
├── build/                      installers
│   ├── install-selected-tools.ps1   pick toolchains   <- start here
│   ├── fetch-tools.ps1             download everything
│   ├── install-tools.ps1           extract everything
│   └── setup-android.ps1           Android SDK packages
├── apps/                       installed toolchains
│   └── 7zip/                   bundled standalone 7-Zip (no host install needed)
├── data/                       everything persistent
│   ├── opencode-data/          chat sessions
│   ├── opencode-config/        settings, providers, auth
│   ├── appdata/                redirected profile writes
│   └── backups/                session snapshots
├── projects/                   put your code here
└── downloads/                  installer cache (safe to delete)
```

---

## Troubleshooting

**`Windows cannot find "\apps\opencode\OpenCode.exe"`**
You launched the binary directly. Use `Launch.cmd`, or option 1 from the menu.

**`The system cannot find the file specified` from the menu**
You are running `Launch.cmd` from inside `bin\`. Run it from the portable root.

**A tool is missing from the Developer Shell**
Re-run `Launch.cmd` → **8** to see which `PATH` entries resolved. Then re-run
the installer for that tool.

**Android SDK manager appears to hang**
It blocks waiting on keyboard input when it inherits a console. The launcher
already handles this; if you call `sdkmanager` yourself, redirect stdin from `NUL`.

**`Not enough free space`**
The installer refuses to start rather than filling your drive. Drop a tool from
the selection, or use a larger stick.

**First launch on a new PC is slow**
Windows Defender and SmartScreen scan each binary from removable media the first
time. This is one-off per machine.

**Verify anything at any time:** `Launch.cmd` → **8**

---

## Requirements

- Windows 10 or 11, 64-bit
- A USB drive — budget 1 GB for OpenCode alone, 6 GB for everything
- Internet access on first run, for downloads

**No 7-Zip needed.** A standalone copy is bundled at `apps\7zip\7za.exe` and the
installers prefer it over anything on the host, so the portable unpacks its own
archives even on a machine where 7-Zip was never installed. Nothing is added to
Windows, and nothing is registered.

---

## Platforms

| Edition | Repository | Launcher |
|---|---|---|
| **Windows 10/11 (x64)** | [`opencode_portable`](https://github.com/palashsuryavanshi/opencode_portable) — *this repo* | `Launch.cmd` |
| **Linux (x64)** | [`opencode-portable-linux`](https://github.com/palashsuryavanshi/opencode-portable-linux) | `./launch.sh` |

Same toolchains, same session layout, same `data/` isolation model. Session
databases are platform-specific, but the launchers and directory structure are
identical, so moving a workflow between the two is straightforward.

---

## License

This packaging is MIT. Each bundled tool remains under its own licence — see
`apps/<tool>/` after installing.