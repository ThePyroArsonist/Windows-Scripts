# Map of VSS writer names to their associated service names
$writerServiceMap = @{
    "ASR Writer"                              = "VSS"
    "BITS Writer"                             = "BITS"
    "Certificate Authority"                   = "CertSvc"
    "COM+ REGDB Writer"                       = "VSS"
    "DFS Replication service writer"          = "DFSR"
    "DHCP Jet Writer"                         = "DHCPServer"
    "FRS Writer"                              = "NtFrs"
    "IIS Config Writer"                       = "AppHostSvc"
    "IIS Metabase Writer"                     = "IISADMIN"
    "Microsoft Exchange Writer"               = "MSExchangeIS"
    "Microsoft Hyper-V VSS Writer"            = "vmms"
    "Microsoft SQL Server VSS Writer"         = "SQLWriter"
    "NPS VSS Writer"                          = "IAS"
    "NTDS"                                    = "NTDS"
    "OSearch VSS Writer"                      = "OSearch"
    "OSearch14 VSS Writer"                    = "OSearch14"
    "Registry Writer"                         = "VSS"
    "Shadow Copy Optimization Writer"         = "VSS"
    "SharePoint Services Writer"              = "SPWriter"
    "SMS Writer"                              = "SMS_SITE_BACKUP"
    "SPP Writer"                              = "sppsvc"
    "System Writer"                           = "CryptSvc"
    "Task Scheduler Writer"                   = "Schedule"
    "TermServLicensing"                       = "TermServLicensing"
    "WMI Writer"                              = "Winmgmt"
    "MSSearch Service Writer"                 = "WSearch"
    "WDS VSS Writer"                          = "WDSServer"
    "WIDWriter"                               = "WIDWriter"
    "WINS Jet Writer"                         = "WINS"
}

# Optional: Services to exclude from restart logic due to known issues
$excludedServices = @("AcronisActiveProtectionService")

# Run and capture output of vssadmin
function Get-VssWriters {
    vssadmin list writers | Out-String
}

# Convert raw vssadmin output to structured objects
function Parse-VssWriters {
    param([string]$writerOutput)

    $lines = $writerOutput -split "`r?`n"
    $result = @()
    $currentWriter = @{}

    foreach ($line in $lines) {
        if ($line -match "^Writer name:\s+(.*)") {
            if ($currentWriter.Count -gt 0) {
                $result += [PSCustomObject]@{
                    WriterName = $currentWriter['WriterName'].Trim().Replace("'","")
                    State      = $currentWriter['State'].Trim()
                    LastError  = $currentWriter['LastError'].Trim()
                }
            }
            $currentWriter = @{
                'WriterName' = $matches[1]
                'State'      = ''
                'LastError'  = ''
            }
        } elseif ($line -match "State:\s+(.+?) \(") {
            $currentWriter['State'] = $matches[1]
        } elseif ($line -match "Last error:\s+(.+)") {
            $currentWriter['LastError'] = $matches[1]
        }
    }

    # Capture the final writer
    if ($currentWriter.Count -gt 0) {
        $result += [PSCustomObject]@{
            WriterName = $currentWriter['WriterName'].Trim().Replace("'","")
            State      = $currentWriter['State'].Trim()
            LastError  = $currentWriter['LastError'].Trim()
        }
    }

    return $result
}

# Restart a service and its dependent services (if possible)
function Restart-ServiceWithDependents {
    param ([string]$ServiceName)

    try {
        $mainService = Get-Service -Name $ServiceName -ErrorAction Stop

        # Get dependent services via WMI
        $dependentNames = Get-WmiObject -Class Win32_DependentService |
            Where-Object { $_.Antecedent -like "*Name=`"$ServiceName`"*"} |
            ForEach-Object {
                ($_."Dependent" -split 'Name="')[1] -replace '"', ''
            }

        $blockingDependents = @()

        if ($dependentNames.Count -gt 0) {
            Write-Output "Stopping dependent services for '$ServiceName': $($dependentNames -join ', ') NEWLINE "

            foreach ($dep in $dependentNames) {
                if ($excludedServices -contains $dep) {
                    Write-Output "Skipping excluded service: $dep NEWLINE "
                    $blockingDependents += $dep
                    continue
                }

                try {
                    $svc = Get-Service -Name $dep -ErrorAction Stop
                    if ($svc.Status -eq 'Running') {
                        Write-Output "Stopping dependent service: $dep NEWLINE "
                        Stop-Service -Name $dep -Force -ErrorAction Stop

                        # Wait up to 20 seconds for the service to stop
                        $svc.WaitForStatus('Stopped', '00:00:20')
                        Write-Output "Stopped dependent: $dep NEWLINE "
                    }
                } catch {
                    Write-Output "Timeout or error stopping dependent service: $dep  NEWLINE "
                    $blockingDependents += $dep
                }
            }

          }

            if ($blockingDependents.Count -gt 0) {
                Write-Output "Aborting restart of '$ServiceName' because these dependents couldn't be stopped: $($blockingDependents -join ', ') NEWLINE "
                return
            }

        # Restart main service
        if ($mainService.Status -eq 'Running') {
            Write-Output "Restarting main service: $ServiceName NEWLINE "
            Restart-Service -Name $ServiceName -Force
        } else {
            Write-Output "Starting main service: $ServiceName NEWLINE "
            Start-Service -Name $ServiceName
        }

        # Restart previously stopped dependents
        foreach ($dep in $dependentNames) {
            if ($excludedServices -contains $dep) { continue }
            try {
                Start-Service -Name $dep -ErrorAction SilentlyContinue
                Write-Output "Restarted dependent: $dep NEWLINE "
            } catch {
                Write-Output "Could not restart dependent: $dep NEWLINE "
            }
        }

        Write-Output "Successfully restarted '$ServiceName' and dependents. NEWLINE "
    }
    catch {
        Write-Output "Failed to restart service '$ServiceName': $_ NEWLINE "
    }
}

# Handles a single faulty writer
function Restart-FaultyWriterService {
    param(
        [string]$writerName,
        [string]$serviceName
    )

    Write-Output " NEWLINE Handling writer: $writerName (Service: $serviceName) NEWLINE "

    if ($excludedServices -contains $serviceName) {
        Write-Output "Service '$serviceName' is excluded from auto-restart. NEWLINE "
        return
    }

    try {
        $dependentCheck = Get-WmiObject -Class Win32_DependentService |
            Where-Object { $_.Antecedent -like "*Name=`"$serviceName`"*"}

        if ($dependentCheck.Count -gt 0) {
            Restart-ServiceWithDependents -ServiceName $serviceName
        } else {
            $svc = Get-Service -Name $serviceName -ErrorAction Stop
            if ($svc.Status -eq 'Running') {
                Restart-Service -Name $serviceName -Force
                Write-Output "Restarted service: $serviceName NEWLINE "
            } else {
                Start-Service -Name $serviceName
                Write-Output "Started service: $serviceName NEWLINE "
            }
        }
    }
    catch {
        Write-Output "Failed to restart '$serviceName' for writer '$writerName': $_ NEWLINE "
    }
}

# MAIN EXECUTION
$originalOutput = Get-VssWriters
$parsedWriters = Parse-VssWriters -writerOutput $originalOutput

Write-Output " NEWLINE === Initial VSS Writer Status === NEWLINE "
$parsedWriters 

# Identify failed writers
$failedWriters = $parsedWriters | Where-Object {
    $_.State -match 'Failed|Retryable error' -or $_.LastError -ne 'No error'
}

if ($failedWriters.Count -eq 0) {
    $source = "VSSHealthCheck"
    if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
        New-EventLog -LogName Application -Source $source
    }
    Write-EventLog -LogName Application -Source $source -EventID 9999 -EntryType Information -Message "All VSS writers are healthy."
    Write-Output " NEWLINE No VSS writer errors found. System is healthy. NEWLINE "
} else {
    Write-Output " NEWLINE Found $($failedWriters.Count) writer(s) with issues. Attempting recovery... NEWLINE "

    foreach ($writer in $failedWriters) {
        $serviceName = $writerServiceMap[$writer.WriterName]
        if ($null -ne $serviceName) {
            Restart-FaultyWriterService -writerName $writer.WriterName -serviceName $serviceName
        } else {
            Write-Output " No known service mapping for writer '$($writer.WriterName)'. Manual review required. NEWLINE "
        }
    }

    Start-Sleep -Seconds 5
    Write-Output " NEWLINE === VSS Writer Status After Recovery Attempt === NEWLINE "
    $finalOutput = Get-VssWriters
    $finalParsed = Parse-VssWriters -writerOutput $finalOutput
    $finalParsed 
}
