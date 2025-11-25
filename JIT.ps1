# ============================================
# NinjaOne JIT Local Admin Elevation (No Scheduled Task)
# With popup notification via msg.exe
# - Uses Script Variables:
#     AccountName   -> Local account to elevate
#     DurationMins  -> How long (minutes) before auto revoke
# - Elevates immediately
# - Sends popup about end time
# - Sleeps
# - Revokes admin
# ============================================

param()

$ErrorActionPreference = "Stop"

# Read from NinjaOne script variables (exposed as environment variables)
$TargetUserRaw      = $env:AccountName
$DurationMinutesRaw = $env:DurationMins

$LogDir  = "C:\ProgramData\NinjaRMMAgent\Logs"
$LogFile = Join-Path $LogDir "JIT_LocalAdmin_Elevation_NoTask.log"

if (!(Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "$timestamp  $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

Log "=== JIT local admin elevation (no scheduled task) start ==="
Log "Raw TargetUser from env: '$TargetUserRaw'"
Log "Raw DurationMinutes from env: '$DurationMinutesRaw'"

# Validate inputs
if ([string]::IsNullOrWhiteSpace($TargetUserRaw)) {
    Log "FATAL ERROR: AccountName script variable is empty"
    throw "AccountName script variable is empty"
}

[int]$DurationMinutes = 0
if (-not [int]::TryParse($DurationMinutesRaw, [ref]$DurationMinutes) -or $DurationMinutes -le 0) {
    Log "FATAL ERROR: DurationMins is invalid or not greater than zero"
    throw "DurationMins must be a positive integer"
}

$TargetUser = $TargetUserRaw

Log "Target user: $TargetUser"
Log "Duration: $DurationMinutes minute(s)"

# Calculate end time and notify
$endTime = (Get-Date).AddMinutes($DurationMinutes)
Log "Admin rights will be revoked at: $endTime"

# Popup notification using msg.exe
try {
    $msgText = "Temporary local admin granted for '$TargetUser' until $endTime.`n`nRights will be removed automatically."
    # Send to all active sessions
    & msg.exe * $msgText 2>$null
    Log "Sent msg popup to logged in users"
}
catch {
    Log "Failed to send msg popup: $($_.Exception.Message)"
}

try {
    # Ensure running elevated
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log "ERROR: Script is not running as admin or SYSTEM"
        throw "Script requires administrative rights"
    }

    # Validate local user exists
    try {
        Get-LocalUser -Name $TargetUser -ErrorAction Stop | Out-Null
        Log "Found local user '$TargetUser'"
    } catch {
        Log "ERROR: '$TargetUser' is not a local user on this system"
        throw
    }

    $adminGroup = "Administrators"

    # Check if already admin
    $alreadyAdmin = $false
    try {
        $members = Get-LocalGroupMember -Group $adminGroup -ErrorAction Stop
        if ($members | Where-Object { $_.Name -like "*\$TargetUser" -or $_.Name -eq $TargetUser }) {
            $alreadyAdmin = $true
        }
    } catch {
        Log "Warning: Could not enumerate Administrators group"
    }

    if (-not $alreadyAdmin) {
        Log "Adding '$TargetUser' to Administrators"
        Add-LocalGroupMember -Group $adminGroup -Member $TargetUser -ErrorAction Stop
        Log "Successfully added '$TargetUser'"
    } else {
        Log "'$TargetUser' is already an admin. Skipping add."
    }

    # Wait for the duration
    $seconds = $DurationMinutes * 60
    Log "Sleeping for $seconds second(s) before revoking admin"
    Start-Sleep -Seconds $seconds

    # Revoke admin
    Log "Attempting to remove '$TargetUser' from Administrators"
    Remove-LocalGroupMember -Group $adminGroup -Member $TargetUser -ErrorAction SilentlyContinue
    Log "Completed revoke for '$TargetUser'"

    Log "=== JIT local admin elevation (no scheduled task) complete ==="
}
catch {
    Log "FATAL ERROR: $($_.Exception.Message)"
    throw
}
