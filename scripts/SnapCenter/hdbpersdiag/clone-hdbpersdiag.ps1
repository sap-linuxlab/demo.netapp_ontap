<#
# 
#>

param(
    [Parameter(Mandatory=$false, HelpMessage="SnapCenter Server")][String]$scServer = $NULL,
    [Parameter(Mandatory=$false, HelpMessage="SnapCenter Username")][String]$scUser = "SCUSER",
    [Parameter(Mandatory=$false, HelpMessage="SnapCenter Password")][String]$scPasswd = "PASSWORD",
    [Parameter(Mandatory=$true, HelpMessage="SAP SID")][String]$sid = $NULL,
    [Parameter(Mandatory=$false, HelpMessage="Source/Backup host")][String]$sourceHost = $NULL,
    [Parameter(Mandatory=$false, HelpMessage="Target/Verification host")][String]$targetHost = "TARGETHOST",
    [Parameter(Mandatory=$false, HelpMessage="Target/Verification SID")][String]$targetSid = "TARGETSID",
    [Parameter(Mandatory=$false, HelpMessage="Target/Verification NFS Export")][String]$targetNFsExport = "TARGETEXPORT",
    [Parameter(Mandatory=$false, HelpMessage="Target/Verification script")][String]$targetScript = "/PATHTOSCRIPT/call-hdbpersdiag-flexclone.sh"
)

Import-Module SnapCenter -DisableNameChecking

function Open-SnapCenter-Connection {
    param(
        [string]$scServer,
        [string]$scUser,
        [string]$scPasswd
    )

    $password = ConvertTo-SecureString $scPasswd -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($scUser, $password)

    $opts = @{
        Credential = $credential
    }
    if ($scServer) {
        $opts.Add("SMSbaseUrl", ("https://{0}:8146" -f $scServer))
    } 
    
    Open-SmConnection @opts
}

function WaitFor-Job {
    param(
        [string]$jobId
    )

    while ($true) {
        $job = Get-SmJobSummaryReport -JobId $jobId
        write-Host ("waiting for job [{0}] - [{1}]" -f  $jobId, $job.Status)

        if (! ($job.Status -eq "Running" -or $job.Status -eq "Queued")) {
            return $job
        }

        Start-Sleep 10
    }

    return $job
}

function Create-Clone {
    param(
        [string]$backupName,
        [string]$sourceHost,
        [string]$verificationHost,
        [string]$uid,
        [string]$postCloneScript,
        [string]$exportIpTarget,
        [string]$targetUid
    )

    $result = New-SmClone -AppPluginCode hana -BackupName $backupName -Resources @{"Host"="$sourceHost";"UID"="$uid"} -CloneToInstance "$verificationHost" -NFSExportIPs $exportIpTarget -CloneUid $targetUid -PostCloneCreateCommands $postCloneScript
 
    return $result
}

function Get-CloneDetails {
    param(
        [string]$jobId,
        [string]$sourceSid
    )

    $result = Get-SmClone | Where-Object { $_.CloneName -match ("__{0}_MDC_{1}" -f $jobId,  $sourceSid)}

    return $result
}

function Validate-CloneRequest {
    param(
        [string]$sourceSid,
        [string]$targetSid,
        [string]$targetHost
    )

    $result = Get-SmClone
    $found = $false
    $clone = $null

    Foreach ($clone in $result) {
        if ( $clone.Resources -match ("Source = {0}", $sourceSid) -and $clone.Resources -match ("Clone = {0}" -f $targetSid)) {
            if ($clone.CloneName -match ("__clone__(\d+)_MDC")) {
                $clone_details = Get-SmCloneReport -JobId $Matches.1
                
                if ($clone_details.CloneHostName -eq $targetHost) {
                    $found = $true
                    break
                }
            }
        }
    }

    if ( $found ) {
        Write-Host "clone already exists"
        return $false
    }

    return $true
}

function Get-LatestBackup {
    param(
        [string]$uid,
        [string]$sourceHost
    )

    $result = Get-SmResourceGroup -ListResources | Where-Object {$_.PluginName -eq "hana" -and $_.Uid -match "$uid"}

    if ($sourceHost) {
        $result = $result | Where-Object {$_.Host -eq "$sourceHost"}
    }

    if (! $result) {
        Write-Host ("no resources matching uid [{0}] and host [{1}] with plugin [hana] found" -f $uid, $sourceHost)
        return $null
    }

    if ($result.Length -gt 1) {
        Write-Host ("UID [{0}] detected on multiple hosts - specify the correct one using parameter -sourceHost based on the candidates listed below" -f $uid)
        foreach ($entry in $result) {
            Write-Host ("candidate: [{0}]" -f $entry.Host)
        }
        exit 1
    }
    
    $backups = Get-SmBackupReport -plugin hana | Where-Object {$_.PluginName -eq "hana" -and $_.Status -eq "Completed" -and $_.JobHost -eq $result.Host -and $_.ProtectionGroupName -match ("_{0}$" -f ($uid -replace "\\\\", "_" ))} | Sort-Object -Property StartDateTime -Descending
    if (! $backups) {
        Write-Host ("no backups found matching uid [{0}], host [{1}], plugin [hana] and status [completed]" -f $uid, $sourceHost)
        return $null
    }

    return $backups[0]
}

<#
# MAIN
#>

Write-Host "Starting verification"

Write-Host "Connecting to SnapCenter"
try {
    Open-SnapCenter-Connection -scServer $scServer -scUser $scUser -scPasswd $scPasswd
} catch {
    Write-Host "Unable to connec to SnapCenter: $_"
    exit 1
}


Write-Host "Validating clone/verification request - check for already existing clones"
$result = Validate-CloneRequest -sourceSid $sid -targetSid $targetSid -targetHost $targetHost
if (! $result) {
    Write-Host ("A clone relationsship between {0} and {1} does already exist" -f $sid, $targetSid)
    exit 1
}

$opts = @{uid = "MDC\\$sid"}
if ($sourceHost) {
    Write-Host ("Get latest backup for [{0}] on host [{1}]" -f $sid, $sourceHost)
    $opts.Add("sourceHost", $sourceHost)
} else {
    Write-Host ("Get latest backup for [{0}]" -f $sid)
}

$backup = Get-LatestBackup @opts

if (! $backup) {
    Write-Host "No backup found"
    exit 1
}

Write-Host ("Found backup name [{0}]" -f $backup.BackupName)

Write-Host ("Creating clone from backup [{0}/{1}/{2}]: [{3}/{4}]" -f $backup.JobHost, $sid, $backup.BackupName, $targetHost, $targetSid) 
$job = Create-Clone -backupName $backup.BackupName -sourceHost $backup.JobHost -verificationHost $targetHost -exportIpTarget $targetNFsExport -uid "MDC\$sid" -targetUid "MDC\$targetSid" -postCloneScript $targetScript

$result = WaitFor-Job -jobId $job.Id

if ((! $result) -or ($result.Status -ne "Completed")) {
    Write-Host ("Creating clone failed: {0}" -f $result.JobError)
    exit 1
}

$clone = Get-CloneDetails -jobId $job.Id -sourceSid $sid

if ($clone) {
    Write-Host ("Removing clone [{0}]" -f $clone.CloneName)
    $job = Remove-SmClone -CloneName $clone.CloneName -PluginCode hana -Confirm:$false

    $result = WaitFor-Job -jobId $job.Id
    if ((! $result) -or ($result.Status -ne "Completed")) {
        Write-Host "removing clone failed"
        exit 1
    }
} else {
    Write-Host "clone not found"
    exit 1
}

Write-Host "Verification completed"