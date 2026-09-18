# upload-internet-to-cft.ps1
# ePlanner Job 3. Runs ON the Internet SFTP server (task scheduler), after Job 2.
# Uploads RTMS batch files from the local ePlanner folder to the CFT SFTP.
#
# Only complete batches are sent: a batch RTMS_<timestamp> is complete when its .zip is
# present. Files are deleted from the local folder only after successful upload
# (put -delete). A failed upload leaves the files in place; the next run retries them.
# CFT limit: no single file may exceed 1 GB (RTMS chunks are capped at 999 MB).
# Exit code: 0 = success or nothing to do, 1 = failure (for Task Scheduler monitoring).

# ---------------------------- CONFIG (UAT) ----------------------------------
$winscp      = "C:\Program Files (x86)\WinSCP\winscp.com"
$logDir      = "<LOGS_FOLDER_ON_THIS_SERVER>"  # e.g. <drive>:\<titan-data>\<server>\usr\<account>\Logs

$localDir    = "<LOCAL_FOLDER_ON_THIS_SERVER>" # folder where Job 2's uploads land,
                                               # e.g. <drive>:\<titan-data>\<server>\usr\<account>\Inbound

$destHost    = "sftp-pw.cft.stack.gov.sg"      # CFT SFTP (from CFT onboarding)
$destPort    = 22
$destUser    = "<CFT_USERNAME>"                # from the CFT credentials provided earlier
$destKey     = "<PATH_TO_PPK_FOR_CFT_ACCOUNT>" # CFT key converted to .ppk (WinSCP / PuTTYgen)
$destPassword = "<CFT_PASSWORD>"                # CFT requires key AND password. Keep the
                                               # password exactly as issued - do NOT escape
                                               # or URL-encode it; it is passed separately
                                               # from the URL so special characters are safe
$destHostKey = "<HOST_KEY>"                # format: <algorithm> <bits> <fingerprint>
                                               # WITHOUT the "SHA256:" prefix, e.g.
                                               #   ssh-rsa 4096 KwDTmSPbMmeZ+nKd....
                                               # WinSCP shows it on first manual connection
$destDir     = "<CFT_WORKFLOW_ID_FOLDER>"      # the Workflow ID folder on CFT
# -----------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# 1. Find complete batches in the local folder (.zip present)
$allFiles = Get-ChildItem -Path $localDir -File | Where-Object { $_.Name -match '^RTMS_.*\.(zip|z\d+)$' }

$sendFiles = @()
foreach ($group in ($allFiles | Group-Object { $_.Name -replace '\.(zip|z\d+)$', '' })) {
    if ($group.Group.Extension -contains '.zip') { $sendFiles += $group.Group }
    else { Write-Output "SKIP: batch $($group.Name) has no .zip yet (still relaying), left in place" }
}

if ($sendFiles.Count -eq 0) { Write-Output "Nothing to transfer."; exit 0 }

# 2. Upload to CFT - split parts first, .zip last; delete local file on success
$sendFiles = $sendFiles | Sort-Object @{Expression = { $_.Extension -eq '.zip' }}, Name

# WinSCP commands are written to a script file rather than passed as arguments:
# Windows PowerShell does not preserve embedded quotes when calling a native program,
# which corrupts the -hostkey and put arguments. The generated file also shows exactly
# what WinSCP was asked to do, which helps when diagnosing a failed run.
$commandFile = Join-Path $logDir "cft_$runId.txt"

$lines = @()
$lines += "option batch abort"
$lines += "option confirm off"
# password is given as a separate -password parameter, never inside the sftp:// URL:
# characters such as @ / : # % in a password break the URL, but are fine here
# (tested: @ / : # % & space ' $ \ are all fine in -password; only a literal " is not supported)
$lines += "open sftp://$destUser@$destHost`:$destPort/ -privatekey=""$destKey"" -password=""$destPassword"" -hostkey=""$destHostKey"""
$lines += "cd ""$destDir"""
# -nopreservetime -nopermissions: CFT does not support setting timestamps/permissions
# after upload (SETSTAT unsupported). Without these, WinSCP reports the upload as failed
# even though the file arrived, and -delete is skipped so the file is re-sent every run.
foreach ($file in $sendFiles) { $lines += "put -delete -nopreservetime -nopermissions ""$($file.FullName)""" }
$lines += "exit"

Set-Content -Path $commandFile -Value $lines -Encoding ASCII

& $winscp "/ini=nul" "/log=$logDir\cft_$runId.log" "/script=$commandFile"

if ($LASTEXITCODE -ne 0) {
    Write-Output "ERROR: upload to CFT failed - files left in $localDir for retry on next run (see cft_$runId.log)"
    exit 1
}

Write-Output "Uploaded $($sendFiles.Count) file(s) to CFT $destDir"
exit 0
