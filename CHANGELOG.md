# Changelog

All notable changes to this project will be documented here.

## [Unreleased]
### Added
- Console-free `Launch.vbs` entrypoint, desktop shortcut and URL/file associations; launch failures and update warnings remain visible as dialogs.
- Windows PowerShell 5.1 CI and isolated regression checks for profile preservation, update rollback, signatures, locking and literal-path downloads.
- Verified downloads using GitHub SHA256 metadata and Brave Authenticode signatures, with staging and rollback.

### Fixed
- Missing properties in existing profile JSON no longer break the patcher; writes preserve unrelated data and keep a backup.
- Installation, the launcher, desktop shortcuts and default-browser registration share one launch configuration.
- Update checks run before launch when Brave is closed; removed flags that globally disable component updates and background networking.
- Release archives include `Launch.vbs`, `MakeDefault.bat`, `make-default.ps1` and all runtime scripts.
- Product-version comparison handles the Chromium major prefix; no stale hardcoded download fallback.
- Paths containing spaces, apostrophes, exclamation marks and brackets are handled without shell interpolation.

### Changed
- Replaced the console-opening `run.bat` and `Launch.bat` entrypoints with `Launch.vbs`.
- Default-browser registration adds a candidate for Windows Settings instead of overwriting protocol defaults.
- Removed unused policy/profile templates and clarified upstream-dependent activation and privacy claims.

## [1.0.0] - 2024
### Added
- Initial release
- Auto-install script
- Bypass mechanism
- Update checker
