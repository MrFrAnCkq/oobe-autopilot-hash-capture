<#
.SYNOPSIS
    Captures the Windows Autopilot hardware hash and writes it to CSV files
    suitable for bulk import into Intune / Windows Autopilot.

    Works unmodified in both scenarios:
      - OOBE (Shift+F10 SYSTEM prompt, before any user account exists)
      - An already-deployed, running device (must be run elevated)

    No network, no MDM enrollment, no PowerShell Gallery modules required.

    Output lands in an Output folder beside this script, so the USB root
    stays down to the launcher, the script and the README:

        Output\AutopilotHashes.csv          cumulative, this is what you import
        Output\Devices\AutopilotHash_*.csv  per-device backup copies

.PARAMETER GroupTag
    Optional Autopilot Group Tag to stamp on this device's row.

.PARAMETER Force
    If this serial number is already in the master CSV, overwrite its row
    instead of skipping it.

.PARAMETER NoPause
    Do not wait for a keypress at the end. Useful for scripted/batch runs.

.NOTES
    IMPORTANT: This file must be saved as ASCII or UTF-8 WITH BOM.
    PowerShell 5.1 reads BOM-less files as Windows-1252, which corrupts any
    non-ASCII character and can silently break string parsing. Keep this
    file 7-bit ASCII only.
#>

param(
    [string]$GroupTag = "",
    [switch]$Force,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = "Autopilot Hash Capture" } catch {}

$script:ExitCode = 0

# Output layout, relative to whichever root we end up writing to:
#     <root>\Output\AutopilotHashes.csv          <- the file you import
#     <root>\Output\Devices\AutopilotHash_*.csv  <- per-device backups
# Keeps the USB root down to the launcher, the script and the README.
$script:OutputSubdir  = "Output"
$script:DevicesSubdir = "Devices"

function Write-Status {
    param([string]$Message = "", [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Stop-Script {
    param([int]$Code = 0)
    Write-Status ""
    if (-not $NoPause) {
        try { Read-Host "Press Enter to close" | Out-Null } catch { Start-Sleep -Seconds 5 }
    }
    exit $Code
}

function Get-ScriptDirectory {
    # Order matters. Prefer the real location of this script/exe so output
    # lands on the USB drive, not in System32 or a ps2exe temp folder.
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($MyInvocation.MyCommand.Path) { return (Split-Path -Parent $MyInvocation.MyCommand.Path) }
    try {
        $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        # Ignore the PowerShell host itself; that would point at System32.
        if ($exe -and ($exe -notmatch '\\(powershell|pwsh|cmd)\.exe$')) {
            return (Split-Path -Parent $exe)
        }
    } catch {}
    return $null
}

function Test-WritableDirectory {
    param([string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
        $probe = Join-Path $Path ("wt_" + [guid]::NewGuid().ToString("N") + ".tmp")
        [IO.File]::WriteAllText($probe, "probe")
        Remove-Item -LiteralPath $probe -Force
        return $true
    } catch {
        return $false
    }
}

function Resolve-OutputDirectory {
    # Returns the Output folder, creating it (and Devices under it) on the
    # first writable root we find. The fallbacks get their own named parent
    # folder so we never drop a bare "Output" onto someone's desktop.
    $roots = New-Object System.Collections.Generic.List[string]
    $sd = Get-ScriptDirectory
    if ($sd) { $roots.Add($sd) }
    $roots.Add((Get-Location).Path)
    if ($env:PUBLIC) { $roots.Add((Join-Path $env:PUBLIC "Desktop\AutopilotHashCapture")) }
    $roots.Add("C:\Temp\AutopilotHashCapture")

    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        # Never dump output into a system folder.
        if ($root -match '(?i)\\Windows(\\|$)') { continue }

        $out = Join-Path $root $script:OutputSubdir
        if (-not (Test-WritableDirectory -Path $out)) { continue }
        if (-not (Test-WritableDirectory -Path (Join-Path $out $script:DevicesSubdir))) { continue }
        return $out
    }
    return $null
}

function Move-LegacyOutput {
    # Versions before 1.1 wrote both CSVs straight into the script folder.
    # Pull anything left there into the new layout, otherwise duplicate
    # detection would silently restart from zero on an upgraded USB stick.
    param([string]$Root, [string]$OutDir, [string]$DevicesDir)

    if ([string]::IsNullOrWhiteSpace($Root)) { return }
    if (-not (Test-Path -LiteralPath $Root)) { return }

    $legacyMaster = Join-Path $Root "AutopilotHashes.csv"
    $newMaster    = Join-Path $OutDir "AutopilotHashes.csv"
    if (Test-Path -LiteralPath $legacyMaster) {
        if (Test-Path -LiteralPath $newMaster) {
            Write-Status "NOTE: An old AutopilotHashes.csv is still in the root folder." "Yellow"
            Write-Status "It is being ignored. Merge it by hand if it holds devices you need." "Yellow"
        } else {
            try {
                Move-Item -LiteralPath $legacyMaster -Destination $newMaster -Force
                Write-Status "Moved the existing AutopilotHashes.csv into the Output folder." "Gray"
            } catch {
                Write-Status "WARNING: Could not move the old AutopilotHashes.csv." "Yellow"
                Write-Status "It will be ignored; merge it by hand if it matters." "Yellow"
            }
        }
    }

    try {
        $moved = 0
        $old = @(Get-ChildItem -LiteralPath $Root -Filter "AutopilotHash_*.csv" -File -ErrorAction SilentlyContinue)
        foreach ($f in $old) {
            $dest = Join-Path $DevicesDir $f.Name
            if (-not (Test-Path -LiteralPath $dest)) {
                Move-Item -LiteralPath $f.FullName -Destination $dest -Force
                $moved++
            }
        }
        if ($moved -gt 0) {
            Write-Status ("Moved {0} old per-device CSV file(s) into Output\{1}." -f $moved, $script:DevicesSubdir) "Gray"
        }
    } catch {}
}

function Get-SafeFileNameFragment {
    param([string]$Text, [string]$Fallback = "UNKNOWN")
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Fallback }
    $clean = $Text.Trim()
    foreach ($c in [IO.Path]::GetInvalidFileNameChars()) {
        $clean = $clean.Replace($c, '_')
    }
    $clean = $clean -replace '\s+', '_'
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    if ([string]::IsNullOrWhiteSpace($clean)) { return $Fallback }
    return $clean
}

Write-Status "=== Autopilot Hardware Hash Capture ===" "Cyan"
Write-Status ""

# --- Environment sanity checks ----------------------------------------------

# 1. Elevation
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Status "ERROR: Not running elevated." "Red"
    Write-Status "Right-click RunMe.bat and choose 'Run as administrator'," "Yellow"
    Write-Status "or launch it from the Shift+F10 prompt during OOBE." "Yellow"
    Stop-Script 1
}

# 2. Bitness. The MDM WMI provider is not reachable from a 32-bit host on x64.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Write-Status "ERROR: Running as a 32-bit process on a 64-bit OS." "Red"
    Write-Status "The MDM WMI provider is not visible from here." "Yellow"
    Write-Status "Relaunch using: %SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" "Yellow"
    Stop-Script 1
}

# 3. WinPE. The hash provider does not exist in WinPE, only in full Windows.
$isWinPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
if ($isWinPE) {
    Write-Status "ERROR: This looks like WinPE (boot media)." "Red"
    Write-Status "The Autopilot hash provider only exists in full Windows." "Yellow"
    Write-Status "Boot the installed OS to OOBE and use Shift+F10 there instead." "Yellow"
    Stop-Script 1
}

# --- Basic device info -------------------------------------------------------
try {
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
    $cs   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $os   = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
} catch {
    Write-Status "ERROR: Could not read basic device info." "Red"
    Write-Status $_.Exception.Message "Red"
    Stop-Script 1
}

$serial    = if ($bios.SerialNumber) { $bios.SerialNumber.Trim() } else { "" }
$make      = if ($cs.Manufacturer)   { $cs.Manufacturer.Trim() }   else { "" }
$model     = if ($cs.Model)          { $cs.Model.Trim() }          else { "" }
$productId = if ($os.SerialNumber)   { $os.SerialNumber.Trim() }   else { "" }

Write-Status "Device : $make $model" "White"
Write-Status "Serial : $serial" "White"

# Whitebox / OEM machines often ship placeholder serials. Autopilot keys on
# serial, so duplicates across machines will collide on import. Warn loudly.
$placeholders = @(
    'Default string', 'System Serial Number', 'To Be Filled By O.E.M.',
    'To be filled by O.E.M.', 'None', 'N/A', '0123456789', 'Not Applicable',
    'Not Specified', 'Chassis Serial Number'
)
$serialSuspect = $false
if ([string]::IsNullOrWhiteSpace($serial)) {
    $serialSuspect = $true
} elseif ($placeholders -contains $serial) {
    $serialSuspect = $true
}
if ($serialSuspect) {
    Write-Status ""
    Write-Status "WARNING: Serial number looks like an OEM placeholder or is blank." "Yellow"
    Write-Status "Autopilot keys on serial number. Multiple machines with this same" "Yellow"
    Write-Status "value will collide on import. Set a real serial in BIOS if you can." "Yellow"
}

# --- Hardware hash -----------------------------------------------------------
Write-Status ""
Write-Status "Reading hardware hash..." "Gray"

$hash = $null
try {
    $dev = Get-CimInstance -Namespace 'root/cimv2/mdm/dmmap' `
                           -ClassName 'MDM_DevDetail_Ext01' `
                           -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" `
                           -ErrorAction Stop
    $hash = $dev.DeviceHardwareData
} catch {
    Write-Status "ERROR: Could not query the MDM hardware hash provider." "Red"
    Write-Status $_.Exception.Message "Red"
    Write-Status "" 
    Write-Status "Most common causes:" "Yellow"
    Write-Status "  - Windows build older than 10 1703" "Yellow"
    Write-Status "  - Stripped LTSC/IoT/embedded image without the MDM stack" "Yellow"
    Write-Status "  - Running in WinPE rather than the installed OS" "Yellow"
    Stop-Script 1
}

if ([string]::IsNullOrWhiteSpace($hash)) {
    Write-Status "ERROR: Hardware hash came back empty." "Red"
    Write-Status "The device likely lacks the TPM/UEFI support Autopilot requires." "Yellow"
    Stop-Script 1
}

$hash = $hash.Trim()
# Sanity check: the hash is base64 and is normally 4000+ characters.
if ($hash.Length -lt 1000 -or $hash -notmatch '^[A-Za-z0-9+/=]+$') {
    Write-Status "WARNING: Hash looks unusual (length $($hash.Length))." "Yellow"
    Write-Status "It will still be written, but verify the import in Intune." "Yellow"
} else {
    Write-Status "Hash captured OK ($($hash.Length) chars)." "Green"
}

# --- Resolve output location -------------------------------------------------
$outDir = Resolve-OutputDirectory
if (-not $outDir) {
    Write-Status "ERROR: No writable output location found." "Red"
    Write-Status "Checked the script folder, current folder, Public Desktop and C:\Temp." "Yellow"
    Write-Status "If the USB is write-protected, flip the lock switch or use another drive." "Yellow"
    Stop-Script 1
}

$devicesDir = Join-Path $outDir $script:DevicesSubdir
Move-LegacyOutput -Root (Split-Path -Parent $outDir) -OutDir $outDir -DevicesDir $devicesDir

$masterCsv     = Join-Path $outDir "AutopilotHashes.csv"
$serialForFile = Get-SafeFileNameFragment -Text $serial -Fallback "NOSERIAL"
$stamp         = Get-Date -Format "yyyyMMdd_HHmmss"
$backupCsv     = Join-Path $devicesDir ("AutopilotHash_{0}_{1}.csv" -f $serialForFile, $stamp)

# Header names and order are exactly what the Intune bulk importer expects.
$row = [PSCustomObject]@{
    "Device Serial Number" = $serial
    "Windows Product ID"   = $productId
    "Hardware Hash"        = $hash
    "Group Tag"            = $GroupTag
}

# ASCII encoding on purpose: PS 5.1's "UTF8" writes a BOM, and a BOM at the
# start of the header row is a classic cause of Intune import failures.
# The hash is base64 and the other fields are ASCII, so nothing is lost.

try {
    $row | Export-Csv -LiteralPath $backupCsv -NoTypeInformation -Encoding ASCII
} catch {
    Write-Status "ERROR: Could not write the per-device backup CSV." "Red"
    Write-Status $_.Exception.Message "Red"
    Stop-Script 1
}

$masterAction = "created"
try {
    if (Test-Path -LiteralPath $masterCsv) {
        $existing = @(Import-Csv -LiteralPath $masterCsv)
        $already  = @($existing | Where-Object { $_."Device Serial Number" -eq $serial })

        if ($already.Count -gt 0 -and -not $Force) {
            $masterAction = "skipped"
        } else {
            if ($already.Count -gt 0) {
                $existing = @($existing | Where-Object { $_."Device Serial Number" -ne $serial })
                $masterAction = "updated"
            } else {
                $masterAction = "appended"
            }
            $combined = @($existing) + @($row)
            # Write to a temp file first so a yanked USB cannot leave a
            # half-written master CSV containing every device collected so far.
            $tmp = "$masterCsv.tmp"
            $combined | Export-Csv -LiteralPath $tmp -NoTypeInformation -Encoding ASCII
            Move-Item -LiteralPath $tmp -Destination $masterCsv -Force
        }
    } else {
        $row | Export-Csv -LiteralPath $masterCsv -NoTypeInformation -Encoding ASCII
    }
} catch {
    Write-Status "ERROR: Could not update the master CSV." "Red"
    Write-Status $_.Exception.Message "Red"
    Write-Status "The per-device backup was still saved: $backupCsv" "Yellow"
    Stop-Script 1
}

# --- Report ------------------------------------------------------------------
$total = 0
try { $total = @(Import-Csv -LiteralPath $masterCsv).Count } catch {}

Write-Status ""
switch ($masterAction) {
    "skipped"  { Write-Status "Serial already present in master CSV. Skipped. Use -Force to overwrite." "Yellow" }
    "updated"  { Write-Status "Existing row for this serial was overwritten." "Green" }
    "appended" { Write-Status "Row appended to master CSV." "Green" }
    "created"  { Write-Status "Master CSV created." "Green" }
}
Write-Status ""
Write-Status "Output folder : $outDir" "White"
Write-Status "Master CSV    : $masterCsv" "White"
Write-Status "Backup CSV    : $backupCsv" "White"
Write-Status "Devices in master CSV: $total" "Cyan"
Write-Status ""
Write-Status "Done. Safe to close this window." "Green"

Stop-Script $script:ExitCode
