# Contributing to BraveOriginFree

Thanks for helping make BraveOriginFree better!

## How to Contribute
1. Fork the repo
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Guidelines
- Only modify scripts, configs, and docs - never Brave binaries
- Run the Windows PowerShell 5.1 checks before submitting changes.
- Keep it simple and portable
- Update docs for user-facing changes

## Verification

From the repository root in Windows PowerShell 5.1:

```powershell
Get-ChildItem tests\*.ps1 | ForEach-Object {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Failed: $($_.Name)" }
}
```

Tests use temporary directories and a loopback HTTP server, not real browser profiles, external downloads or registry associations. CI also parses every PowerShell script. The release workflow requires these checks before downloading and packaging Brave.

For an end-to-end smoke check, copy the repository to a disposable Windows folder, run `src\update.ps1`, launch a disposable profile with `Launch.vbs`, close Brave, then run `src\package.ps1`. Confirm the ZIP includes `Launch.vbs` and the default-browser scripts but no `data/` directory. This downloads the official browser; it is separate from the offline regression checks. Do not exercise `MakeDefault.bat` against your real defaults just to test packaging.

## Reporting Bugs
Use issue templates with clear reproduction steps.
