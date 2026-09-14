# Release verification

Run the automated and visual preview checks in Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ReleaseCandidate.ps1 -PreviewOnly
```

For a real clean-profile smoke test, publish the sample release assets, then pass its HTTPS manifest URL without `-PreviewOnly`. Record the native folder chooser, clipboard, initial guide foreground presentation followed by normal window z-order, Chrome discovery, and final **Load unpacked** result in the generated evidence JSON.

The release matrix requires separate observations on Windows 10 and Windows 11. On a managed test device, record the message shown when script execution or Chrome extension policy is blocked. Do not change or bypass policy for the test.

The smoke test must use a standard user account. The evidence records whether the process was elevated and lists any remaining manual observations instead of silently claiming them.
