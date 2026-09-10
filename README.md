AUTOPILOT HASH CAPTURE USB - README
====================================

WHAT THIS DOES
--------------
Reads the device's Autopilot hardware hash from the built-in MDM bridge
WMI provider and writes it to CSV, ready for manual bulk import into
Intune / Windows Autopilot.

No internet. No MDM enrollment. No PowerShell Gallery modules.
Everything it touches ships with Windows.

Every run:
  - Appends/updates a row in Output\AutopilotHashes.csv (one cumulative
    file, so you can run this across a whole batch of machines and hand
    Intune a single CSV). Duplicate serials are skipped unless you pass
    -Force.
  - Also writes a per-device backup to Output\Devices\


FILES AND FOLDERS
-----------------
  RunMe.bat               <- double-click this, only this
  Get-AutopilotHash.ps1   <- does the work, called by RunMe.bat
  README.md               <- this file
  Output\                 <- created on first run
    AutopilotHashes.csv                   <- upload THIS to Intune
    Devices\
      AutopilotHash_<Serial>_<time>.csv   <- one per machine, backup copies

Nothing is written to the USB root, so it stays readable across a batch of
machines. If the drive is write-protected the whole Output folder is
recreated under the fallback location instead (see TROUBLESHOOTING).

Upgrading from an older copy: if AutopilotHashes.csv or any
AutopilotHash_*.csv files are still sitting in the root from a previous
version, the first run moves them into the new layout, so serials you have
already collected still count for duplicate detection.


SCENARIO 1 - AT OOBE
--------------------
1. On the region / "connect to a network" screen, press Shift+F10.
   (That prompt already runs as SYSTEM, so no UAC prompt appears.)
2. Plug in the USB drive.
3. Find its letter:   wmic logicaldisk get caption,volumename
4. Run:               E:\AutopilotHashCapture\RunMe.bat
5. Read the console output, then close it and continue or shut down.


SCENARIO 2 - DEPLOYED / RUNNING DEVICE
--------------------------------------
1. Plug in the USB, open it in Explorer.
2. Double-click RunMe.bat.
3. Accept the UAC prompt.


OPTIONS
-------
  RunMe.bat -GroupTag "Batch-01"         stamp a Group Tag on the row
  RunMe.bat -Force                       overwrite an existing serial's row
  RunMe.bat -NoPause                     don't wait for a keypress at the end

Double-clicking with no arguments leaves Group Tag blank; you can fill it
in later in Intune or edit the CSV.


AFTER COLLECTING
----------------
Intune admin center > Devices > Enrollment > Windows Autopilot Devices >
Import, and upload Output\AutopilotHashes.csv. (Or the Partner Center
equivalent.) The per-device files in Output\Devices\ are backups only -
you do not need to upload them.


WHAT THE SCRIPT CHECKS BEFORE IT RUNS
-------------------------------------
  - Elevation. Tells you plainly if you're not admin/SYSTEM.
  - Bitness. The MDM WMI provider is invisible from a 32-bit process on a
    64-bit OS. The launcher forces the 64-bit PowerShell host via Sysnative,
    and the script refuses to continue if it somehow lands 32-bit anyway.
  - WinPE. The hash provider does NOT exist in WinPE/boot media. If you're
    in WinPE it says so instead of failing cryptically. Boot the installed
    OS to OOBE and use Shift+F10 there.
  - Placeholder serials. Whitebox and some OEM boards report things like
    "Default string" or "To Be Filled By O.E.M." for the serial. Autopilot
    keys on serial number, so several such machines will collide on import.
    The script warns you loudly rather than silently poisoning your CSV.
  - Hash sanity. Verifies the hash is base64 and a plausible length before
    calling it good.


ENCODING - IMPORTANT IF YOU EDIT THESE FILES
--------------------------------------------
Get-AutopilotHash.ps1 is deliberately 7-bit ASCII, and must stay that way.

PowerShell 5.1 reads .ps1 files with no byte-order-mark as Windows-1252,
not UTF-8. A UTF-8 em-dash (bytes E2 80 94) then decodes to three
characters ending in U+201D - a smart closing quote - which PowerShell
accepts as a string terminator. The result is a cascade of bogus
"string is missing the terminator" and "missing closing }" parser errors
pointing at lines nowhere near the real problem.

If you edit the script, either keep it ASCII-only or save it as
UTF-8 WITH BOM. Do not paste in smart quotes, em-dashes, or accented
characters from a word processor.

RunMe.bat is ASCII with CRLF line endings. Batch files need CRLF; if you
edit it on Linux/Mac make sure your editor preserves that.


OUTPUT ENCODING
---------------
CSVs are written as ASCII on purpose. PowerShell 5.1's -Encoding UTF8
writes a BOM, and a BOM in front of the header row is a well-known cause
of Intune Autopilot import failures. The hash is base64 and the other
fields are plain ASCII, so nothing is lost.

The master CSV is written to a .tmp file inside Output\ and then moved
into place, so
yanking the USB mid-write can't corrupt a file that already holds every
device you've collected.


OPTIONAL: SINGLE .EXE
---------------------
If you want one file with no visible .bat/.ps1, compile on any Windows box:

    Install-Module ps2exe -Scope CurrentUser
    Invoke-ps2exe .\Get-AutopilotHash.ps1 .\AutopilotHashCapture.exe -requireAdmin

ps2exe extracts to a temp folder at runtime, so $PSScriptRoot is not the
USB path. The script handles this by falling back to the running exe's
real location, but test it once on a spare machine before relying on it
across a whole batch - confirm the Output folder actually lands on the USB
and not in a temp folder.


TROUBLESHOOTING
---------------
"Not running elevated"
    Right-click RunMe.bat > Run as administrator, or use Shift+F10 at OOBE.

"No writable output location found"
    USB is write-protected or full. Check the physical lock switch.
    Output falls back to %PUBLIC%\Desktop\AutopilotHashCapture\Output,
    then C:\Temp\AutopilotHashCapture\Output.

"Could not query the MDM hardware hash provider"
    Windows older than 10 1703, a stripped LTSC/IoT image, or WinPE.

"Hardware hash came back empty"
    Device lacks the TPM/UEFI support Autopilot requires.

## Attribution

This tool independently implements the publicly documented technique of
reading the Autopilot hardware hash from the `MDM_DevDetail_Ext01` WMI
class. It shares no code with, and was not derived from, any existing
script. Credit to Michael Niehaus's `Get-WindowsAutoPilotInfo`
(MIT-licensed, PowerShell Gallery) for popularizing this approach in the
IT community - worth a look if you also want online/direct-registration
to Autopilot rather than the offline CSV-capture workflow this tool
focuses on.

## License

MIT - see [LICENSE](LICENSE). Copyright (c) 2026 MrFrAnCkq.

## A note on what you commit

The script writes real device serials and hardware hashes into `Output/`.
Those identify specific machines, so keep them out of the repository - the
included `.gitignore` already excludes `Output/` and any stray `*.csv`.
