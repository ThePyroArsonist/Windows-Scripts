# ============================================================
# Windows Defender Full Removal Script
# TrustedInstaller / SYSTEM / PsExec Auto-Download
# ============================================================

param(
    [switch]$TrustedInstaller
)

# ------------------------------------------------------------
# Logging Setup
# ------------------------------------------------------------

$LogDir = "C:\Logs"
$ScriptDir = $PSScriptRoot
$ExternalFiles = @("Ps*")
$LogFile = "$LogDir\DefenderRemoval.log"

if (!(Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

Start-Transcript -Path $LogFile -Append

function Write-Log {
    param([string]$msg)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$time] $msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

Write-Log "==== Script Started ===="

# ------------------------------------------------------------
# PsExec Auto-Download
# ------------------------------------------------------------

$PsExecPath = Join-Path $PSScriptRoot "PsExec.exe"

if (!(Test-Path $PsExecPath)) {
    Write-Log "PsExec.exe not found, downloading..."
    $url = "https://download.sysinternals.com/files/PSTools.zip"
    $zipPath = Join-Path $env:TEMP "PSTools.zip"
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $PSScriptRoot -Force
    Remove-Item $zipPath
    Write-Log "PsExec.exe downloaded and extracted to script folder"
}

# ------------------------------------------------------------
# TrustedInstaller Elevation
# ------------------------------------------------------------

function Invoke-TrustedInstaller {

    Write-Log "Starting TrustedInstaller service..."
    sc.exe start TrustedInstaller | Out-Null

    Write-Log "Launching script in SYSTEM context via PsExec..."
    $cmd = "-accepteula -i -s powershell.exe -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TrustedInstaller"
    Start-Process $PsExecPath -ArgumentList $cmd -Wait

    Write-Log "Relaunch attempted, exiting original script"
    Stop-Transcript
    exit
}

if (-not $TrustedInstaller) {
    Invoke-TrustedInstaller
}

Write-Log "Running in elevated SYSTEM context"

# ------------------------------------------------------------
# Function to run commands as TrustedInstaller
# ------------------------------------------------------------

function Run-AsTrustedInstaller {
    param([string]$Command)
    # Wrap in cmd to call sc.exe start TrustedInstaller
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c sc start TrustedInstaller & $Command" -Wait
}

# ------------------------------------------------------------
# Stop Defender Services
# ------------------------------------------------------------

$services = @(
"WinDefend",
"WdNisSvc",
"SgrmBroker",
"SecurityHealthService",
"Sense",
"wscsvc"
)

foreach ($svc in $services) {
    Write-Log "Stopping service: $svc"
    Stop-Service $svc -Force -ErrorAction SilentlyContinue
    sc.exe config $svc start= disabled | Out-Null
}

# ------------------------------------------------------------
# Disable Defender / SmartScreen Policies
# ------------------------------------------------------------

Write-Log "Disabling Defender policies..."
$policy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
New-Item $policy -Force | Out-Null
Set-ItemProperty $policy DisableAntiSpyware 1
Set-ItemProperty $policy DisableRealtimeMonitoring 1
Set-ItemProperty $policy DisableAntiVirus 1
Set-ItemProperty $policy DisableSpecialRunningModes 1

Write-Log "Disabling SmartScreen..."
$sys = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
New-Item $sys -Force | Out-Null
Set-ItemProperty $sys EnableSmartScreen 0

# ------------------------------------------------------------
# Disable VBS / Memory Integrity
# ------------------------------------------------------------

Write-Log "Disabling virtualization-based security..."
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 0 /f
bcdedit /set hypervisorlaunchtype off

# ------------------------------------------------------------
# Remove Defender Scheduled Tasks
# ------------------------------------------------------------

Write-Log "Removing Defender scheduled tasks..."
Get-ScheduledTask | Where {$_.TaskPath -like "*Windows Defender*"} |
ForEach {
    Write-Log "Removing task: $($_.TaskName)"
    Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false
}

# ------------------------------------------------------------
# Remove Windows Security / Defender Appx Packages
# ------------------------------------------------------------

$packages = @(
"Microsoft.Windows.Defender",
"Microsoft.Windows.SecHealthUI",
"Microsoft.Windows.DefenderFeatures",
"Microsoft.Windows.DefenderApplicationGuard"
)

foreach ($pkg in $packages) {
    Write-Log "Removing Appx package: $pkg"
    Get-AppxPackage -AllUsers *$pkg* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where {$_.PackageName -like "*$pkg*"} |
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------
# Remove Defender Drivers
# ------------------------------------------------------------

$drivers = @("wdboot","wdfilter","wdnisdrv","wdnisproxy")

foreach ($drv in $drivers) {
    Write-Log "Removing driver: $drv"
    sc.exe stop $drv 2>$null
    sc.exe delete $drv 2>$null
}

# ------------------------------------------------------------
# Remove Defender Directories
# ------------------------------------------------------------

$paths = @(
"C:\ProgramData\Microsoft\Windows Defender",
"C:\Program Files\Windows Defender",
"C:\Program Files\Windows Defender Advanced Threat Protection",
"C:\ProgramData\Microsoft\Windows Defender Advanced Threat Protection"
)

foreach ($p in $paths) {
    Write-Log "Removing directory: $p"
    takeown /F $p /R /D Y 2>$null
    icacls $p /grant administrators:F /T 2>$null
    Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------
# Remove Defender WMI Entries
# ------------------------------------------------------------

Write-Log "Cleaning WMI Defender entries..."
Get-WmiObject -Namespace "root\SecurityCenter2" -Class AntiVirusProduct -ErrorAction SilentlyContinue | Remove-WmiObject

# ------------------------------------------------------------
# Disable Security Center
# ------------------------------------------------------------

Write-Log "Disabling Windows Security Center..."
sc.exe stop wscsvc
sc.exe config wscsvc start= disabled

# ------------------------------------------------
# Cleanup Files
# ------------------------------------------------
Write-Host "[*] Cleaning up files..."
foreach ($file in $ExternalFiles) {
    $path = Join-Path $ScriptDir $file
    if (Test-Path $path) {
        try {
            Remove-Item $path -Force -ErrorAction Stop
            Write-Host "[+] Removed $file"
        } catch {
            Write-Host "[!] Could not remove $file: ${_}"
        }
    }
}

# ------------------------------------------------------------
# Completion
# ------------------------------------------------------------

Write-Log "====================================="
Write-Log "Windows Defender removal completed"
Write-Log "System reboot required"
Write-Log "====================================="

Stop-Transcript
