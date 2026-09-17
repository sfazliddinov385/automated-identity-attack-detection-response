# Pure response logic. Dot-source without starting HTTP or importing AD.
# The HTTP service and the local approval tool share this request format.
Set-StrictMode -Version Latest

function Write-SOARJson {
    param([string]$Path, [object]$Value)
    $Temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($Temporary, ($Value | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
        # Never overwrite an existing decision or result.
        [IO.File]::Move($Temporary, $Path)
    }
    finally {
        if (Test-Path -LiteralPath $Temporary) { Remove-Item -LiteralPath $Temporary -Force }
    }
}

function Initialize-SOARState {
    param([string]$StateRoot)
    foreach ($Name in @('requests', 'approvals', 'processing', 'results')) {
        New-Item -ItemType Directory -Path (Join-Path $StateRoot $Name) -Force | Out-Null
    }
}

function Get-SOARRequest {
    param([Parameter(Mandatory)]$Payload)
    $AllowedUsers = @('spray.user01', 'spray.user02', 'spray.user03', 'spray.user04', 'spray.user05')
    foreach ($Field in @('detection', 'severity', 'source_ip', 'domain', 'event_time', 'targeted_accounts', 'targeted_users')) {
        if ($null -eq $Payload.PSObject.Properties[$Field]) { throw "Missing alert field: $Field" }
    }
    if ($Payload.detection -cne 'Password Spraying Detected' -or $Payload.severity -cne 'High') {
        throw 'Unexpected detection or severity.'
    }
    if ([string]$Payload.domain -ine 'LAB') { throw 'Unexpected domain.' }
    $Address = $null
    if (-not [Net.IPAddress]::TryParse([string]$Payload.source_ip, [ref]$Address)) { throw 'Invalid source IP.' }
    $EventTime = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Payload.event_time, [ref]$EventTime)) { throw 'Invalid event time.' }
    $RawUsers = @($Payload.targeted_users)
    $Users = @($RawUsers | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
    # The deployed lab response is deliberately limited to this exact set.
    if ([string]$Payload.targeted_accounts -cne '5' -or $RawUsers.Count -ne 5 -or $Users.Count -ne 5) {
        throw 'Exactly five unique lab accounts are required.'
    }
    foreach ($User in $Users) {
        if ($AllowedUsers -notcontains $User) { throw "Account is not allowlisted: $User" }
    }
    $Normalized = [ordered]@{
        version = 2
        detection = 'Password Spraying Detected'
        severity = 'High'
        source_ip = $Address.ToString()
        domain = 'LAB'
        event_time = $EventTime.ToUniversalTime().ToString('o')
        targeted_accounts = 5
        targeted_users = $Users
    }
    $Canonical = $Normalized | ConvertTo-Json -Depth 5 -Compress
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $Id = -join ($Hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Canonical)) | ForEach-Object { $_.ToString('x2') })
    }
    finally { $Hasher.Dispose() }
    [PSCustomObject]@{ request_id = $Id; payload = [PSCustomObject]$Normalized }
}

function New-SOARApproval {
    param(
        [Parameter(Mandatory)][string]$StateRoot,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$RequestId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ApprovedBy,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason,
        [ValidateRange(1, 30)][int]$ValidForMinutes = 15
    )
    # This function is local-only. Never expose it through an HTTP route.
    if ([string]::IsNullOrWhiteSpace($Reason) -or [string]::IsNullOrWhiteSpace($ApprovedBy)) {
        throw 'Approval identity and reason are required.'
    }
    $RequestPath = Join-Path $StateRoot "requests/$RequestId.json"
    $Saved = Get-Content -LiteralPath $RequestPath -Raw -ErrorAction Stop | ConvertFrom-Json
    $Request = Get-SOARRequest $Saved.payload
    if ($Request.request_id -cne $RequestId) { throw 'Stored request does not match its ID.' }
    if ((Test-Path (Join-Path $StateRoot "processing/$RequestId.lock")) -or
        (Test-Path (Join-Path $StateRoot "results/$RequestId.json"))) {
        throw 'This request has already started. Inspect its result before any manual recovery.'
    }
    $Now = [DateTimeOffset]::UtcNow
    $Approval = [ordered]@{
        request_id = $RequestId
        decision = 'approve'
        approved_by = $ApprovedBy
        reason = $Reason
        approved_at = $Now.ToString('o')
        expires_at = $Now.AddMinutes($ValidForMinutes).ToString('o')
    }
    Write-SOARJson -Path (Join-Path $StateRoot "approvals/$RequestId.json") -Value $Approval
    [PSCustomObject]$Approval
}

function New-SOARReply {
    param([int]$StatusCode, [hashtable]$Body)
    [PSCustomObject]@{ StatusCode = $StatusCode; Body = $Body }
}

function Invoke-SOARResponse {
    param(
        [Parameter(Mandatory)]$Payload,
        [Parameter(Mandatory)][string]$StateRoot,
        [bool]$DryRun = $true,
        [string]$DirectoryServer = 'localhost',
        [ValidateRange(1, 5)][int]$VerificationAttempts = 3,
        [ValidateRange(0, 5)][int]$VerificationDelaySeconds = 1
    )
    $AllowedOu = 'OU=SOAR-Lab-Users,DC=lab,DC=local'
    try { $Request = Get-SOARRequest $Payload }
    catch { return New-SOARReply 400 @{ success = $false; status = 'rejected'; reason = $_.Exception.Message } }
    Initialize-SOARState $StateRoot
    $Id = $Request.request_id
    $ResultPath = Join-Path $StateRoot "results/$Id.json"
    $LockPath = Join-Path $StateRoot "processing/$Id.lock"
    $ApprovalPath = Join-Path $StateRoot "approvals/$Id.json"

    if (-not $DryRun -and (Test-Path -LiteralPath $ResultPath)) {
        $Previous = Get-Content -LiteralPath $ResultPath -Raw -ErrorAction Stop | ConvertFrom-Json
        return New-SOARReply 200 @{
            success = [bool]$Previous.success; status = 'already_processed'; request_id = $Id
            cached = $true; previous_result = $Previous
            message = 'Historical result only; no action or fresh state check was performed.'
        }
    }
    if (-not $DryRun -and (Test-Path -LiteralPath $LockPath)) {
        return New-SOARReply 409 @{
            success = $false; status = 'requires_review'; request_id = $Id
            reason = 'This request started without a saved final result. Inspect AD and audit logs; do not retry automatically.'
        }
    }

    $Approval = $null
    if (-not $DryRun) {
        $RequestPath = Join-Path $StateRoot "requests/$Id.json"
        if (-not (Test-Path -LiteralPath $RequestPath)) {
            Write-SOARJson -Path $RequestPath -Value @{
                request_id = $Id; received_at = [DateTimeOffset]::UtcNow.ToString('o'); payload = $Request.payload
            }
        }
        if (-not (Test-Path -LiteralPath $ApprovalPath)) {
            return New-SOARReply 202 @{
                success = $false; status = 'pending_approval'; request_id = $Id; dry_run = $false
                message = 'A local operator must review and approve this exact request. No accounts were changed.'
            }
        }
        try {
            $Approval = Get-Content -LiteralPath $ApprovalPath -Raw -ErrorAction Stop | ConvertFrom-Json
            $Issued = [DateTimeOffset]::Parse($Approval.approved_at)
            $Expiry = [DateTimeOffset]::Parse($Approval.expires_at)
            $Now = [DateTimeOffset]::UtcNow
            if ($Approval.request_id -cne $Id -or $Approval.decision -cne 'approve' -or
                [string]::IsNullOrWhiteSpace($Approval.approved_by) -or [string]::IsNullOrWhiteSpace($Approval.reason) -or
                $Issued -gt $Now -or $Expiry -le $Now -or $Expiry -le $Issued -or
                ($Expiry - $Issued).TotalMinutes -gt 30) { throw 'Invalid or expired approval.' }
        }
        catch {
            return New-SOARReply 403 @{ success = $false; status = 'approval_rejected'; request_id = $Id; reason = 'Approval is invalid or expired. Local review is required.' }
        }
    }

    # Validate every identity before making any changes, including its current OU.
    $Accounts = @()
    try {
        foreach ($Name in $Request.payload.targeted_users) {
            $User = Get-ADUser -Identity $Name -Properties Enabled -Server $DirectoryServer -ErrorAction Stop
            if (-not $User.DistinguishedName.EndsWith(",$AllowedOu", [StringComparison]::OrdinalIgnoreCase)) {
                throw "Account is outside the authorized OU: $Name"
            }
            $Accounts += $User
        }
    }
    catch {
        return New-SOARReply 409 @{ success = $false; status = 'preflight_failed'; request_id = $Id; reason = $_.Exception.Message }
    }

    if ($DryRun) {
        $Preview = @($Accounts | ForEach-Object {
            [PSCustomObject]@{ user = $_.SamAccountName; action = $(if ($_.Enabled) { 'WouldDisable' } else { 'AlreadyDisabled' }) }
        })
        return New-SOARReply 200 @{
            success = $false; status = 'dry_run'; dry_run = $true; verified = $false
            request_id = $Id; results = $Preview; message = 'Preview only; no approval consumed and no accounts changed.'
        }
    }

    # Atomic, durable claim BEFORE side effects. A crash requires manual review.
    if ([DateTimeOffset]::Parse($Approval.expires_at) -le [DateTimeOffset]::UtcNow) {
        return New-SOARReply 403 @{ success = $false; status = 'approval_rejected'; request_id = $Id; reason = 'Approval expired during preflight.' }
    }
    try {
        $Lock = [IO.File]::Open($LockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $Lock.Dispose()
    }
    catch {
        return New-SOARReply 409 @{ success = $false; status = 'requires_review'; request_id = $Id; reason = 'Unable to claim request safely.' }
    }
    # Preserve the approval for audit; the processing claim prevents its reuse.
    $Results = @()
    foreach ($User in $Accounts) {
        $Action = 'AlreadyDisabled'
        $Verified = $false
        $EnabledAfter = $null
        $ErrorText = $null
        try {
            if ($User.Enabled) {
                $Action = 'DisableFailed'
                Disable-ADAccount -Identity $User.DistinguishedName -Server $DirectoryServer -Confirm:$false -ErrorAction Stop
                $Action = 'Disabled'
            }
            for ($Attempt = 1; $Attempt -le $VerificationAttempts; $Attempt++) {
                $Current = Get-ADUser -Identity $User.DistinguishedName -Properties Enabled -Server $DirectoryServer -ErrorAction Stop
                $EnabledAfter = [bool]$Current.Enabled
                if (-not $EnabledAfter) { $Verified = $true; break }
                if ($Attempt -lt $VerificationAttempts) { Start-Sleep -Seconds $VerificationDelaySeconds }
            }
            if (-not $Verified) { $ErrorText = 'Account remained enabled after verification attempts.' }
        }
        catch { $ErrorText = $_.Exception.Message }
        $Results += [PSCustomObject]@{
            user = $User.SamAccountName; action = $Action; verified = $Verified
            enabled_after = $EnabledAfter; error = $ErrorText
        }
    }
    $VerifiedCount = @($Results | Where-Object { $_.verified }).Count
    $Success = $VerifiedCount -eq $Accounts.Count
    $Body = @{
        success = $Success; status = $(if ($Success) { 'verified' } else { 'partial_failure' })
        request_id = $Id; dry_run = $false; verified = $Success; cached = $false
        requested_accounts = $Accounts.Count; verified_accounts = $VerifiedCount
        directory_server = $DirectoryServer; verified_at = [DateTimeOffset]::UtcNow.ToString('o')
        approved_by = $Approval.approved_by; approval_reason = $Approval.reason
        approval_time = $Approval.approved_at; source_ip = $Request.payload.source_ip
        needs_review = (-not $Success); results = $Results
        audit_4725 = 'Separate Splunk audit check required; AD state readback is the automatic verification.'
    }
    Write-SOARJson -Path $ResultPath -Value $Body
    return New-SOARReply $(if ($Success) { 200 } else { 500 }) $Body
}
