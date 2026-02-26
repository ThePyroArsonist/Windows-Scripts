# ============================================================
# Disable LLMNR, mDNS, and NetBIOS
# Run as Administrator
# ============================================================

Write-Host "Disabling LLMNR..." -ForegroundColor Cyan

# Disable LLMNR via Group Policy registry key
New-Item -Path "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient" `
    -Name "EnableMulticast" -Type DWord -Value 0

Write-Host "LLMNR Disabled." -ForegroundColor Green


Write-Host "Disabling mDNS..." -ForegroundColor Cyan

# Disable mDNS via registry
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" `
    -Name "EnableMDNS" -Type DWord -Value 0

Write-Host "mDNS Disabled." -ForegroundColor Green


Write-Host "Disabling NetBIOS over TCP/IP..." -ForegroundColor Cyan

# Disable NetBIOS on all network adapters
$adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True"

foreach ($adapter in $adapters) {
    $adapter.SetTcpipNetbios(2) | Out-Null
}

Write-Host "NetBIOS Disabled on all active adapters." -ForegroundColor Green


Write-Host "`nAll settings applied, verifying configuration." -ForegroundColor Yellow

Write-Host "Setting should display EnableMulticast : 0" -ForegroundColor Green
Get-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient"

Write-Host "Setting should display EnableMDNS : 0" -ForegroundColor Green
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"

Write-Host "Setting should display 2 for each network adapter" -ForegroundColor Green
Get-WmiObject Win32_NetworkAdapterConfiguration | 
Where-Object {$_.IPEnabled} | 
Select Description, TcpipNetbiosOptions
