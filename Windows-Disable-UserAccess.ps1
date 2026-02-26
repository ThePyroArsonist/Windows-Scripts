param (
    [Parameter(Mandatory)]
    [string]$Username
)

Write-Host "Restricting access for user: $Username" -ForegroundColor Cyan

# ------------------------------------------------------------------
# 1. Deny Local & Remote Interactive Logon
# ------------------------------------------------------------------

secedit /export /cfg C:\temp_secpol.cfg

(gc C:\temp_secpol.cfg) `
    -replace "SeDenyInteractiveLogonRight =",
             "SeDenyInteractiveLogonRight = $Username" `
    -replace "SeDenyRemoteInteractiveLogonRight =",
             "SeDenyRemoteInteractiveLogonRight = $Username" |
    sc C:\temp_secpol.cfg

secedit /configure /db secedit.sdb /cfg C:\temp_secpol.cfg /areas USER_RIGHTS

Remove-Item C:\temp_secpol.cfg -Force

Write-Host "Logon denied." -ForegroundColor Green

# ------------------------------------------------------------------
# 2. Disable Shell Access
# ------------------------------------------------------------------

$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

Set-ItemProperty -Path $regPath -Name "Shell" -Value ""

Write-Host "Shell access disabled." -ForegroundColor Green

# ------------------------------------------------------------------
# 3. Remove SSH Access (Windows OpenSSH)
# ------------------------------------------------------------------

$sshGroup = "SSH Users"

if (Get-LocalGroup -Name $sshGroup -ErrorAction SilentlyContinue) {
    Remove-LocalGroupMember -Group $sshGroup -Member $Username -ErrorAction SilentlyContinue
}

Write-Host "SSH access removed." -ForegroundColor Green

# ------------------------------------------------------------------
# 4. Disable Port Forwarding / Tunneling
# ------------------------------------------------------------------

netsh interface portproxy reset

Write-Host "Port forwarding cleared." -ForegroundColor Green

Write-Host "`nUser $Username is fully restricted. Rebooting Workstation." -ForegroundColor Yellow


Restart-Computer -Force
