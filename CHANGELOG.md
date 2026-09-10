# Changelog

## 1.1.0
- Output moved out of the USB root. The root now holds only RunMe.bat,
  Get-AutopilotHash.ps1 and the README.
- Cumulative CSV is now Output\AutopilotHashes.csv; per-device backups go
  to Output\Devices\. Both folders are created on first run.
- One-time migration: an AutopilotHashes.csv or AutopilotHash_*.csv files
  left in the root by 1.0.0 are moved into the new layout on first run, so
  duplicate detection keeps working on an upgraded USB stick.
- Fallback locations are now %PUBLIC%\Desktop\AutopilotHashCapture and
  C:\Temp\AutopilotHashCapture (each with the same Output layout inside),
  so a write-protected USB no longer drops loose CSVs on the Public Desktop.
- Final report prints the output folder alongside the two file paths.

## 1.0.0
- Initial public release.
- Reads the Autopilot hardware hash via the built-in MDM_DevDetail_Ext01
  WMI provider - no network, MDM enrollment, or PowerShell Gallery
  modules required.
- Works unmodified at OOBE (Shift+F10) and on deployed/running devices.
- Writes a cumulative AutopilotHashes.csv (ready for Intune bulk import)
  plus a per-device timestamped backup CSV.
- Elevation, bitness, and WinPE environment checks with plain-language
  error messages.
- Placeholder-serial detection (whitebox/OEM boards reporting things
  like "Default string" or "To Be Filled By O.E.M.").
- Hash format/length sanity check.
- ASCII-only CSV and script encoding to avoid BOM-related Intune import
  failures and PowerShell 5.1's Windows-1252 fallback parsing issue.
- Master CSV writes go through a .tmp file + atomic move so an
  interrupted USB pull can't corrupt previously collected rows.
