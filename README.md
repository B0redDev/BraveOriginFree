<div align="center">

# Brave Origin Free for Windows

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6.svg)]()
[![Brave Origin](https://img.shields.io/badge/Brave%20Origin-Latest-FB542B.svg)](https://github.com/brave/brave-browser/releases)
[![GitHub stars](https://img.shields.io/github/stars/thesajidalam/BraveOriginFree?style=social)](https://github.com/thesajidalam/BraveOriginFree/stargazers)
[![GitHub release](https://img.shields.io/github/v/release/thesajidalam/BraveOriginFree)](https://github.com/thesajidalam/BraveOriginFree/releases)

**Brave Origin costs $60 on Windows. On Linux it's free. This fixes that.**

[Download Latest](https://github.com/thesajidalam/BraveOriginFree/releases/latest) • [Live Demo](https://braveorigin.vercel.app) • [Report Bug](https://github.com/thesajidalam/BraveOriginFree/issues/new?template=bug_report.yml) • [Request Feature](https://github.com/thesajidalam/BraveOriginFree/issues/new?template=feature_request.yml)

</div>

---

## ✨ What's New in Latest Version

- **One launch path** - `Launch.vbs`, the desktop shortcut and default-browser registration start `src/launch.ps1` without opening a console.
- **Verified updates** - Downloads require the official GitHub asset SHA256 digest and a valid Brave Authenticode signature before replacing the installed browser.
- **Profile safety** - Existing settings are preserved; writes use an exclusive lock, atomic replacement and a backup.
- **Windows checks** - Regression checks run under Windows PowerShell 5.1 before releases are published.

---

## 📖 About

This is a portable Windows x64 wrapper around the official Brave Origin build, not a browser fork. It configures a separate profile and requests that optional Brave features be disabled through launch flags.

The activation configuration depends on Brave's implementation and may stop working after an upstream update. Feature availability, privacy behavior and license terms are determined by Brave; this repository does not establish that bypassing a purchase requirement is permitted.

---

## 🚀 Quick Start

### Installation (First Time)
1. [Download the latest release](https://github.com/thesajidalam/BraveOriginFree/releases/latest) or clone this repo
2. Extract the folder to any location (Works on USB drives too!)
3. Double-click `install.bat`
4. Done! A desktop shortcut will be created

### Launching
- **Launch:** Double-click `Launch.vbs` to start without a terminal window.
- **Desktop Shortcut:** Use "Brave Origin (Free)" shortcut

Launch failures and update warnings appear as dialogs instead of disappearing into a hidden terminal. Installation and manual maintenance still use PowerShell. For detailed diagnostics, run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File src\launch.ps1` from this folder. Windows Script Host and the Windows VBScript feature must be enabled.

### Make it Default Browser
1. Run `MakeDefault.bat`
2. Follow the prompts
3. Choose it in `Windows Settings → Apps → Default apps → Brave Origin Free`.

Registration writes per-user registry entries, but does not override Windows' default-app selection. After moving the folder, rerun `install.bat` to refresh the shortcut and `MakeDefault.bat` to refresh registration.

---

## 🔧 Features

| Feature | Status |
| --- | --- |
| Brave Shields, bookmarks and history | Provided by the official browser |
| Rewards, Wallet, Leo AI, News, Talk, VPN, Tor | Disabling requested via shared launch flags |
| P3A and Ads telemetry | Disabling requested; absence of telemetry is not guaranteed |
| Portable, no admin rights required | Yes; use a writable folder |
| Updates | Checked before launch when no Brave process is running |
| Windows support | Windows 10/11 x64, Windows PowerShell 5.1 |

### Updates and recovery

The launcher installs the latest stable Origin build when needed. A download can delay startup. There is no background updater or scheduled task; close **all** Brave processes and launch again to check for updates. Component updates and background networking are not globally disabled.

If an update fails, an existing browser with a valid Brave signature can still launch with a warning. A first installation fails instead. Do not treat offline fallback as confirmation that the installed version is current.

Manual commands:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File src\update.ps1 -CheckOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File src\update.ps1
```

The updater checks the archive SHA256 against GitHub release metadata and checks `brave.exe`'s signer and product version. Missing verification metadata is an error. Downloads and extraction happen in a staging directory; failed replacement rolls back to the previous directory. The updater never changes the profile. If rollback itself fails, the error names the `.update-...\previous` recovery directory; do not delete it.

---

## 🛠️ How It Works

The patcher writes these local activation keys:
```json
{"brave":{"origin":{"purchase_validated":true}},"skus":{"state":{"67":"{\"credentials\":{\"items\":{\"6\":\"7\"}}}"}}}
```
The script only changes local configuration; it does not verify that Brave accepts it or guarantee the browser's network behavior.

Close all Brave processes before patching. Explicit `-ProfilePath` can initialize a new profile; malformed JSON or unexpected object types are rejected without replacing existing data. A changed existing `Local State` is backed up as `Local State.braveoriginfree.bak`; an already-configured file is left untouched. `-Status` exits 0 only when both configured keys match, otherwise 1.

---

## 📂 Project Structure

```
BraveOriginFree/
├── install.bat       # Verified setup and desktop shortcut
├── Launch.vbs        # Console-free launcher
├── MakeDefault.bat   # Register a default-browser candidate
├── make-default.ps1  # Per-user registration
├── src/
│   ├── install.ps1   # Setup using the verified updater
│   ├── launch.ps1    # Update check, profile setup and launch flags
│   ├── runtime.ps1   # Shared Windows helpers
│   ├── bypass.ps1    # Safe profile patcher
│   ├── update.ps1    # Verified, staged installation/update
│   └── package.ps1   # Release archive builder
├── tests/            # Isolated PowerShell regression checks
└── README.md
```

---

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- [Report a Bug](https://github.com/thesajidalam/BraveOriginFree/issues/new?template=bug_report.yml)
- [Request a Feature](https://github.com/thesajidalam/BraveOriginFree/issues/new?template=feature_request.yml)
- [Submit a Pull Request](https://github.com/thesajidalam/BraveOriginFree/pulls)

---

## 📜 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

**Disclaimer:** Brave Origin is a product of [Brave Software](https://brave.com). The MIT license here covers this project's code, not a grant of rights to Brave's products or services. Downloads use official Brave GitHub releases; local configuration does not guarantee continued activation.
