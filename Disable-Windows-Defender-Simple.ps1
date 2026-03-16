# ==============================
# Windows Defender Removal Script
# Needs to run as Administrator
# ==============================

Write-Host "Stopping Defender services..."

$services = @(
"WinDefend",
"WdNisSvc",
"Sense",
"SgrmBroker",
"SecurityHealthService",
"wscsvc"
)

foreach ($svc in $services) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
}

Write-Host "Disabling Defender via registry..."

$paths = @(
"HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender",
"HKLM:\SOFTWARE\Microsoft\Windows Defender"
)

foreach ($p in $paths) {
    New-Item -Path $p -Force | Out-Null
}

Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name DisableAntiSpyware -Value 1 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name DisableRealtimeMonitoring -Value 1 -Type DWord

Write-Host "Disabling SmartScreen..."

New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name EnableSmartScreen -Value 0 -Type DWord

Write-Host "Disabling VBS / Hypervisor..."

bcdedit /set hypervisorlaunchtype off | Out-Null

Write-Host "Removing Windows Security App..."

$remove_appx = @("SecHealthUI")

foreach ($app in $remove_appx) {

    Get-AppxPackage -AllUsers | Where-Object {$_.Name -like "*$app*"} | ForEach-Object {
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }

    Get-AppxProvisionedPackage -Online | Where-Object {$_.PackageName -like "*$app*"} | ForEach-Object {
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue
    }
}

Write-Host "Removing Defender scheduled tasks..."

$tasks = @(
"\Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance",
"\Microsoft\Windows\Windows Defender\Windows Defender Cleanup",
"\Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan",
"\Microsoft\Windows\Windows Defender\Windows Defender Verification"
)

foreach ($task in $tasks) {
    schtasks /Delete /TN $task /F 2>$null
}

Write-Host "Removing Defender directories..."

$paths = @(
"C:\ProgramData\Microsoft\Windows Defender",
"C:\Program Files\Windows Defender",
"C:\Program Files\Windows Defender Advanced Threat Protection"
)

foreach ($path in $paths) {
    Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Defender removal completed."
Write-Host "Reboot required."
