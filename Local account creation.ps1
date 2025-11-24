# =============================================
# Local User Creation for NinjaOne
# Non interactive, parameter based
#
# Expected NinjaOne script variables (Windows)
# Need to create four parameters in NinjaOne enviornment:
#   AccountName       - new local account name
#   Password          - password for the account
#   ConfirmPassword   - same password again for validation
#   AdminOrStandard   - "Admin" or "Standard" (case insensitive)
#
# The script:
#   1. Validates parameters
#   2. Ensures the user does not already exist
#   3. Creates the local account
#   4. Adds the user to "Users"
#   5. Optionally adds the user to "Administrators" based on AdminOrStandard
#   6. Forces password change at next logon
#   7. Logs actions to C:\ProgramData\NinjaRMMAgent\Logs
# =============================================

$ErrorActionPreference = "Stop"

# Logging setup
$LogRoot = "C:\ProgramData\NinjaRMMAgent\Logs"
$LogFile = Join-Path $LogRoot "Create_Local_User_Ninja.log"

if (-not (Test-Path $LogRoot)) {
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
}

function Log {
    param([string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "$ts  $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

Log "============================================"
Log " Local User Creation Script (NinjaOne)"
Log "============================================"
Log "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Log "Machine: $env:COMPUTERNAME"
Log ""

# Read parameters from environment
$UserName        = $env:AccountName
$PasswordPlain   = $env:Password
$ConfirmPlain    = $env:ConfirmPassword
$AccountTypeRaw  = $env:AdminOrStandard

# Fallback if someone used AccountType instead of AdminOrStandard
if (-not $AccountTypeRaw) {
    $AccountTypeRaw = $env:AccountType
}

# Validate parameters
if ([string]::IsNullOrWhiteSpace($UserName)) {
    Log "ERROR AccountName parameter is missing or empty"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($PasswordPlain)) {
    Log "ERROR Password parameter is missing or empty"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($ConfirmPlain)) {
    Log "ERROR ConfirmPassword parameter is missing or empty"
    exit 1
}

if ($PasswordPlain -ne $ConfirmPlain) {
    Log "ERROR Password and ConfirmPassword do not match"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($AccountTypeRaw)) {
    Log "WARN AdminOrStandard parameter is missing  defaulting to Standard"
    $AccountTypeRaw = "Standard"
}

$AccountType = $AccountTypeRaw.Trim()
Log "Input parameters"
Log "  AccountName      = $UserName"
Log "  AccountType      = $AccountType"
Log ""

# Check if user already exists
try {
    $existing = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($existing) {
        Log "ERROR Local user '$UserName' already exists  aborting"
        exit 1
    }
}
catch {
    Log "ERROR Failed to query local users  $($_.Exception.Message)"
    exit 1
}

# Convert password to SecureString
try {
    $securePassword = ConvertTo-SecureString -String $PasswordPlain -AsPlainText -Force
}
catch {
    Log "ERROR Failed to convert password to SecureString  $($_.Exception.Message)"
    exit 1
}

# Create local user
try {
    Log "Creating local user '$UserName'"
    New-LocalUser -Name $UserName -Password $securePassword -FullName $UserName -Description "Created via NinjaOne script" -ErrorAction Stop

    Enable-LocalUser -Name $UserName -ErrorAction Stop
    Log "User '$UserName' created and enabled"

    # Add to Users group to ensure visibility in Control Panel and Settings
    Add-LocalGroupMember -Group "Users" -Member $UserName -ErrorAction SilentlyContinue
    Log "Added '$UserName' to 'Users' group"
}
catch {
    Log "ERROR Failed to create or enable user '$UserName'  $($_.Exception.Message)"
    exit 1
}

# Force password change at next logon
try {
    Log "Flagging '$UserName' to change password at next logon"
    $adsiUser = [ADSI]"WinNT://$env:COMPUTERNAME/$UserName,user"
    $adsiUser.PasswordExpired = 1
    $adsiUser.SetInfo()
    Log "Successfully set PasswordExpired flag for '$UserName'"
}
catch {
    Log "WARN Could not set password change at next logon for '$UserName'  $($_.Exception.Message)"
}

# Decide admin or standard
$makeAdmin = $false
switch -Regex ($AccountType.ToLower()) {
    "admin"         { $makeAdmin = $true }
    "administrator" { $makeAdmin = $true }
    "std"           { $makeAdmin = $false }
    "standard"      { $makeAdmin = $false }
    default {
        Log "WARN Unknown AdminOrStandard value '$AccountType'  defaulting to Standard"
        $makeAdmin = $false
    }
}

if ($makeAdmin) {
    try {
        Add-LocalGroupMember -Group "Administrators" -Member $UserName -ErrorAction Stop
        Log "Added '$UserName' to 'Administrators' group (admin account)"
    }
    catch {
        Log "ERROR Failed to add '$UserName' to Administrators group  $($_.Exception.Message)"
        # Keep going  user still exists as standard
    }
}
else {
    Log "Account type set to Standard  '$UserName' will not be added to Administrators"
}

Log "Local user '$UserName' creation complete"
Log "============================================"
exit 0
