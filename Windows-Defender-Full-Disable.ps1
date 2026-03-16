# ============================================================
# Windows Defender Full Removal Script
# TrustedInstaller Execution
# ============================================================

param(
    [switch]$TrustedInstaller
)

# ------------------------------------------------------------
# Self Elevation to TrustedInstaller
# ------------------------------------------------------------

function Invoke-TrustedInstaller {
    Write-Host "[*] Launching TrustedInstaller context..."
    sc.exe start TrustedInstaller | Out-Null
    $taskName = "TI-Launcher-$([guid]::NewGuid())"
    $cmd = "powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TrustedInstaller"
    schtasks /Create /TN $taskName /SC ONCE /ST 00:00 /RL HIGHEST /RU SYSTEM /TR $cmd /F | Out-Null
    schtasks /Run /TN $taskName | Out-Null

    exit
}

if (-not $TrustedInstaller) {
    Invoke-TrustedInstaller
}

Write-Host "[+] Running as TrustedInstaller equivalent"

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

    Stop-Service $svc -Force -ErrorAction SilentlyContinue
    sc.exe config $svc start= disabled | Out-Null

}

# ------------------------------------------------------------
# Disable Defender Policies
# ------------------------------------------------------------

Write-Host "[*] Disabling Defender policies via Registry..."

$policy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"

New-Item $policy -Force | Out-Null

Set-ItemProperty $policy DisableAntiSpyware 1
Set-ItemProperty $policy DisableRealtimeMonitoring 1
Set-ItemProperty $policy DisableAntiVirus 1
Set-ItemProperty $policy DisableSpecialRunningModes 1

# ------------------------------------------------------------
# Disable SmartScreen
# ------------------------------------------------------------

Write-Host "[*] Disabling SmartScreen..."

$sys = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"

New-Item $sys -Force | Out-Null

Set-ItemProperty $sys EnableSmartScreen 0

# ------------------------------------------------------------
# Disable VBS / Memory Integrity
# ------------------------------------------------------------

Write-Host "[*] Disabling virtualization security..."

reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 0 /f

bcdedit /set hypervisorlaunchtype off

# ------------------------------------------------------------
# Remove Defender Scheduled Tasks
# ------------------------------------------------------------

Write-Host "[*] Removing Defender scheduled tasks..."

Get-ScheduledTask | Where {

    $_.TaskPath -like "*Windows Defender*"

} | ForEach {

    Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false

}

# ------------------------------------------------------------
# Remove Windows Security App
# ------------------------------------------------------------

Write-Host "[*] Removing Windows Security UI..."

Get-AppxPackage -AllUsers *SecHealthUI* | Remove-AppxPackage -AllUsers
Get-AppxProvisionedPackage -Online | Where {$_.PackageName -like "*SecHealthUI*"} | Remove-AppxProvisionedPackage -Online

# ------------------------------------------------------------
# Remove Defender Platform Packages
# ------------------------------------------------------------

Write-Host "[*] Removing Defender platform..."

$packages = @(
"Microsoft.Windows.Defender",
"Microsoft.Windows.SecHealthUI",
"Microsoft.Windows.DefenderFeatures",
"Microsoft.Windows.DefenderApplicationGuard"
)

foreach ($pkg in $packages) {

    Get-AppxPackage -AllUsers *$pkg* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

}

# ------------------------------------------------------------
# Remove Defender Drivers
# ------------------------------------------------------------

Write-Host "[*] Removing Defender drivers..."

$drivers = @(
"wdboot",
"wdfilter",
"wdnisdrv",
"wdnisproxy"
)

foreach ($drv in $drivers) {

    sc.exe stop $drv 2>$null
    sc.exe delete $drv 2>$null

}

# ------------------------------------------------------------
# Remove Defender Directories
# ------------------------------------------------------------

Write-Host "[*] Removing Defender files..."

$paths = @(
"C:\ProgramData\Microsoft\Windows Defender",
"C:\Program Files\Windows Defender",
"C:\Program Files\Windows Defender Advanced Threat Protection",
"C:\ProgramData\Microsoft\Windows Defender Advanced Threat Protection"
)

foreach ($p in $paths) {

    takeown /F $p /R /D Y 2>$null
    icacls $p /grant administrators:F /T 2>$null
    Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue

}

# ------------------------------------------------------------
# Disable Security Center Integration
# ------------------------------------------------------------

Write-Host "[*] Disabling Windows Security Center..."

sc.exe stop wscsvc
sc.exe config wscsvc start= disabled

# ------------------------------------------------------------
# Remove Defender WMI providers
# ------------------------------------------------------------

Write-Host "[*] Cleaning WMI Defender namespaces..."

Get-WmiObject -Namespace "root\SecurityCenter2" -Class AntiVirusProduct -ErrorAction SilentlyContinue | Remove-WmiObject

# ------------------------------------------------------------
# Completion
# ------------------------------------------------------------

Write-Host ""
Write-Host "====================================="
Write-Host "Windows Defender removal completed"
Write-Host "Reboot the system to finalize changes"
Write-Host "====================================="
