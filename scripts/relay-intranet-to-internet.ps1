# relay-intranet-to-internet.ps1
# ePlanner Job 2. Runs ON the Intranet SFTP server (task scheduler).
# Uploads RTMS batch files from the local ePlanner folder to the Internet SFTP.
#
# Only complete batches are sent: a batch RTMS_<timestamp> is complete when its .zip is
# present (RTMS uploads the split parts .z01.. first and the .zip last).
# Files are deleted from the local folder only after successful upload (put -delete).
# A failed upload leaves the files in place; the next run retries them automatically.
# Exit code: 0 = success or nothing to do, 1 = failure (for Task Scheduler monitoring).

# ---------------------------- CONFIG (UAT) ----------------------------------
$winscp      = "C:\Program Files (x86)\WinSCP\winscp.com"
$logDir      = "<LOGS_FOLDER_ON_THIS_SERVER>"

$localDir    = "<LOCAL_EPLANNER_FOLDER>"

$destHost    = "<INTERNET_SFTP_HOST>"          # NPUCMSFTPSVRI01 (UAT) / NPCMSFTPSVRI01 (PROD)
$destPort    = 22
$destUser    = "gcci-uat-rtms-eplanner"        # PROD: gcci-prd-rtms-eplanner
$destKey     = "<PATH_TO_PPK_FOR_INTERNET_ACCOUNT>"
$destHostKey = "<INTERNET_HOST_KEY>"
$destDir     = "<EPLANNER_DIR_ON_INTERNET>"
# -----------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# 1. Find complete batches in the local folder (.zip present)
$allFiles = Get-ChildItem -Path $localDir -File | Where-Object { $_.Name -match '^RTMS_.*\.(zip|z\d+)$' }

$sendFiles = @()
foreach ($group in ($allFiles | Group-Object { $_.Name -replace '\.(zip|z\d+)$', '' })) {
    if ($group.Group.Extension -contains '.zip') { $sendFiles += $group.Group }
    else { Write-Output "SKIP: batch $($group.Name) has no .zip yet (still uploading), left in place" }
}

if ($sendFiles.Count -eq 0) { Write-Output "Nothing to transfer."; exit 0 }

# 2. Upload to the Internet SFTP - split parts first, .zip last; delete local file on success
$sendFiles = $sendFiles | Sort-Object @{Expression = { $_.Extension -eq '.zip' }}, Name

# WinSCP commands are written to a script file rather than passed as arguments:
# Windows PowerShell does not preserve embedded quotes when calling a native program,
# which corrupts the -hostkey and put arguments. The generated file also shows exactly
# what WinSCP was asked to do, which helps when diagnosing a failed run.
$commandFile = Join-Path $logDir "relay_$runId.txt"

$lines = @()
$lines += "option batch abort"
$lines += "option confirm off"
$lines += "open sftp://$destUser@$destHost`:$destPort/ -privatekey=""$destKey"" -hostkey=""$destHostKey"""
$lines += "cd ""$destDir"""
foreach ($file in $sendFiles) { $lines += "put -delete ""$($file.FullName)""" }
$lines += "exit"

Set-Content -Path $commandFile -Value $lines -Encoding ASCII

& $winscp "/ini=nul" "/log=$logDir\relay_$runId.log" "/script=$commandFile"

if ($LASTEXITCODE -ne 0) {
    Write-Output "ERROR: upload to $destHost failed - files left in $localDir for retry on next run (see relay_$runId.log)"
    exit 1
}

Write-Output "Uploaded $($sendFiles.Count) file(s) to $destHost$destDir"
exit 0
