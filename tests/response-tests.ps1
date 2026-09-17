# Self-contained tests. All AD calls are fakes; no module, domain, or credentials needed.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Repo = Split-Path -Parent $PSScriptRoot
$ParseFailure = $false
Get-ChildItem -Path $Repo -Filter '*.ps1' -Recurse | ForEach-Object {
    $Tokens = $null; $ParseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$Tokens, [ref]$ParseErrors) | Out-Null
    if ($ParseErrors.Count) { $ParseErrors | Format-List; $ParseFailure = $true }
}
if ($ParseFailure) { throw 'PowerShell syntax validation failed.' }
. (Join-Path $Repo 'windows-responder/SOAR-ResponseCore.ps1')
$TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('soar-tests-' + [guid]::NewGuid().ToString('N'))
$script:Passed = 0; $script:Failed = 0

function Assert-Equal($Actual, $Expected) {
    if ($Actual -ne $Expected) { throw "Expected [$Expected], received [$Actual]." }
}
function Assert-Throws([scriptblock]$Operation) {
    $Thrown = $false
    try { & $Operation | Out-Null } catch { $Thrown = $true }
    if (-not $Thrown) { throw 'Expected an exception.' }
}
function Reset-Fixture {
    $script:State = Join-Path $TestRoot ([guid]::NewGuid().ToString('N'))
    Initialize-SOARState $script:State
    $script:Accounts = @{}; $script:Writes = @(); $script:ReadServers = @()
    $script:DisableFailure = ''; $script:NoChange = ''; $script:ReadFailure = ''
    1..5 | ForEach-Object {
        $Name = 'spray.user{0:D2}' -f $_
        $script:Accounts[$Name] = [PSCustomObject]@{
            SamAccountName = $Name; Enabled = $true
            DistinguishedName = "CN=$Name,OU=SOAR-Lab-Users,DC=lab,DC=local"
        }
    }
    $script:Payload = [PSCustomObject]@{
        detection = 'Password Spraying Detected'; severity = 'High'; domain = 'LAB'
        source_ip = '192.168.226.133'; event_time = '2026-08-20T18:16:00Z'
        targeted_accounts = 5; targeted_users = @($script:Accounts.Keys | Sort-Object)
    }
}
function Get-ADUser {
    [CmdletBinding()]
    param([string]$Identity, [string[]]$Properties, [string]$Server)
    $script:ReadServers += $Server
    $Name = $Identity
    if ($Identity.StartsWith('CN=')) { $Name = ($Identity -split ',')[0].Substring(3) }
    if (-not $script:Accounts.ContainsKey($Name)) { throw 'Account missing.' }
    if ($Identity.StartsWith('CN=') -and $Name -eq $script:ReadFailure) { throw 'Readback unavailable.' }
    $Account = $script:Accounts[$Name]
    [PSCustomObject]@{ SamAccountName = $Name; Enabled = $Account.Enabled; DistinguishedName = $Account.DistinguishedName }
}
function Disable-ADAccount {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Identity, [string]$Server)
    $Name = ($Identity -split ',')[0].Substring(3)
    $script:Writes += $Name
    if ($Server -cne 'dc-test') { throw 'Write used a different DC.' }
    if ($Name -eq $script:DisableFailure) { throw 'Simulated permission failure.' }
    if ($Name -ne $script:NoChange) { $script:Accounts[$Name].Enabled = $false }
}
function Invoke-TestResponse([bool]$DryRun = $false) {
    Invoke-SOARResponse -Payload $script:Payload -StateRoot $script:State -DryRun $DryRun -DirectoryServer 'dc-test' -VerificationDelaySeconds 0
}
function Approve-Fixture {
    $Pending = Invoke-TestResponse
    Assert-Equal $Pending.StatusCode 202
    New-SOARApproval -StateRoot $script:State -RequestId $Pending.Body.request_id -ApprovedBy 'LAB\reviewer' -Reason 'Reviewed controlled lab test and account impact.' | Out-Null
    $Pending.Body.request_id
}
function Run-Case([string]$Name, [scriptblock]$Test) {
    Reset-Fixture
    try { & $Test; $script:Passed++; Write-Host "PASS $Name" }
    catch { $script:Failed++; Write-Host "FAIL $Name : $($_.Exception.Message)`n$($_.ScriptStackTrace)" }
}

try {
    Run-Case 'Live request without approval makes no AD changes' {
        $Reply = Invoke-TestResponse
        Assert-Equal $Reply.StatusCode 202
        Assert-Equal $Reply.Body.status 'pending_approval'
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'A caller cannot self-approve in JSON' {
        $script:Payload | Add-Member approved $true
        $script:Payload | Add-Member approval ([PSCustomObject]@{ decision = 'approve'; approved_by = 'admin' })
        Assert-Equal (Invoke-TestResponse).StatusCode 202
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'Repeated pending requests keep a stable ID' {
        $First = Invoke-TestResponse; $Second = Invoke-TestResponse
        Assert-Equal $First.Body.request_id $Second.Body.request_id
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'Dry run does not claim a verified response' {
        $Reply = Invoke-TestResponse $true
        Assert-Equal $Reply.Body.status 'dry_run'
        Assert-Equal $Reply.Body.success $false
        Assert-Equal $Reply.Body.verified $false
        Assert-Equal $Reply.Body.results.Count 5
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'Approved request verifies all five accounts on the same DC' {
        $Id = Approve-Fixture; $Reply = Invoke-TestResponse
        Assert-Equal $Reply.StatusCode 200
        Assert-Equal $Reply.Body.status 'verified'
        Assert-Equal $Reply.Body.verified_accounts 5
        Assert-Equal $Reply.Body.success $true
        Assert-Equal $script:Writes.Count 5
        Assert-Equal @($script:ReadServers | Where-Object { $_ -ne 'dc-test' }).Count 0
        Assert-Equal (Test-Path (Join-Path $script:State "results/$Id.json")) $true
    }
    Run-Case 'Already-disabled users are verified without another disable call' {
        $Id = Approve-Fixture
        foreach ($User in $script:Accounts.Values) { $User.Enabled = $false }
        $Reply = Invoke-TestResponse
        Assert-Equal $Reply.Body.success $true
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'Changed source cannot reuse an approval' {
        $Id = Approve-Fixture; $script:Payload.source_ip = '192.168.226.140'
        Assert-Equal (Invoke-TestResponse).StatusCode 202
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'Changed event time cannot reuse an approval' {
        $Id = Approve-Fixture; $script:Payload.event_time = '2026-08-20T18:17:00Z'
        Assert-Equal (Invoke-TestResponse).StatusCode 202
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'User array order does not change request identity' {
        $First = Get-SOARRequest $script:Payload
        [array]::Reverse($script:Payload.targeted_users)
        Assert-Equal (Get-SOARRequest $script:Payload).request_id $First.request_id
    }
    Run-Case 'Equivalent timestamp offsets preserve approval identity' {
        $First = Get-SOARRequest $script:Payload
        $script:Payload.event_time = '2026-08-20T13:16:00-05:00'
        Assert-Equal (Get-SOARRequest $script:Payload).request_id $First.request_id
    }
    Run-Case 'JSON DateTime values preserve UTC identity' {
        $First = Get-SOARRequest $script:Payload
        $script:Payload.event_time = [DateTime]::SpecifyKind([DateTime]::new(2026, 8, 20, 18, 16, 0), [DateTimeKind]::Utc)
        Assert-Equal (Get-SOARRequest $script:Payload).request_id $First.request_id
    }
    Run-Case 'Ambiguous timestamps without a time zone are rejected' {
        $script:Payload.event_time = '2026-08-20T18:16:00'
        Assert-Equal (Invoke-TestResponse).StatusCode 400
    }
    Run-Case 'Expired approval fails closed' {
        $Id = Approve-Fixture; $Path = Join-Path $script:State "approvals/$Id.json"
        $Grant = Get-Content $Path -Raw | ConvertFrom-Json
        $Grant.approved_at = [DateTimeOffset]::UtcNow.AddMinutes(-20).ToString('o')
        $Grant.expires_at = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')
        $Grant | ConvertTo-Json | Set-Content $Path
        Assert-Equal (Invoke-TestResponse).StatusCode 403
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'Malformed approval fails closed' {
        $Id = Approve-Fixture
        Set-Content (Join-Path $script:State "approvals/$Id.json") '{bad'
        Assert-Equal (Invoke-TestResponse).StatusCode 403
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'Approval copied from another request fails closed' {
        $Id = Approve-Fixture; $Path = Join-Path $script:State "approvals/$Id.json"
        $Grant = Get-Content $Path -Raw | ConvertFrom-Json
        $Grant.request_id = ('a' * 64)
        $Grant | ConvertTo-Json | Set-Content $Path
        Assert-Equal (Invoke-TestResponse).StatusCode 403
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'Approval cannot be overwritten' {
        $Id = Approve-Fixture
        Assert-Throws { New-SOARApproval -StateRoot $script:State -RequestId $Id -ApprovedBy 'LAB\reviewer' -Reason 'Second decision' }
    }
    Run-Case 'An account moved outside the OU prevents every change' {
        $Id = Approve-Fixture
        $script:Accounts['spray.user05'].DistinguishedName = 'CN=spray.user05,OU=Other,DC=lab,DC=local'
        Assert-Equal (Invoke-TestResponse).Body.status 'preflight_failed'
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'Missing AD account prevents every change' {
        $Id = Approve-Fixture; $script:Accounts.Remove('spray.user05')
        Assert-Equal (Invoke-TestResponse).Body.status 'preflight_failed'
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'An unapproved username is rejected' {
        $script:Payload.targeted_users[4] = 'Administrator'
        Assert-Equal (Invoke-TestResponse).StatusCode 400
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'Mismatched account count is rejected' {
        $script:Payload.targeted_accounts = 6
        Assert-Equal (Invoke-TestResponse).StatusCode 400
    }
    Run-Case 'Duplicate users are rejected' {
        $script:Payload.targeted_users[4] = 'spray.user01'
        Assert-Equal (Invoke-TestResponse).StatusCode 400
    }
    Run-Case 'Wrong domain is rejected' {
        $script:Payload.domain = 'OTHER'
        Assert-Equal (Invoke-TestResponse).StatusCode 400
    }
    Run-Case 'Wrong severity is rejected' {
        $script:Payload.severity = 'Low'
        Assert-Equal (Invoke-TestResponse).StatusCode 400
    }
    Run-Case 'Wrong detection is rejected' {
        $script:Payload.detection = 'Something Else'
        Assert-Equal (Invoke-TestResponse).StatusCode 400
    }
    Run-Case 'Missing event time is rejected' {
        $script:Payload.PSObject.Properties.Remove('event_time')
        Assert-Equal (Invoke-TestResponse).StatusCode 400
    }
    Run-Case 'Malformed source IP is rejected' {
        $script:Payload.source_ip = '../../approvals'
        Assert-Equal (Invoke-TestResponse).StatusCode 400
    }
    Run-Case 'One failed disable reports partial failure' {
        $Id = Approve-Fixture; $script:DisableFailure = 'spray.user03'
        $Reply = Invoke-TestResponse
        Assert-Equal $Reply.StatusCode 500
        Assert-Equal $Reply.Body.success $false
        Assert-Equal $Reply.Body.verified_accounts 4
        Assert-Equal $Reply.Body.needs_review $true
    }
    Run-Case 'A command returning without changing AD is not success' {
        $Id = Approve-Fixture; $script:NoChange = 'spray.user03'
        $Reply = Invoke-TestResponse
        Assert-Equal $Reply.Body.success $false
        Assert-Equal $Reply.Body.verified_accounts 4
    }
    Run-Case 'A readback failure is not success' {
        $Id = Approve-Fixture; $script:ReadFailure = 'spray.user03'
        Assert-Equal (Invoke-TestResponse).Body.success $false
    }
    Run-Case 'Replay returns historical evidence without repeating changes' {
        $Id = Approve-Fixture; $First = Invoke-TestResponse
        $script:Accounts['spray.user01'].Enabled = $true
        $Reply = Invoke-TestResponse
        Assert-Equal $Reply.Body.status 'already_processed'
        Assert-Equal $Reply.Body.cached $true
        Assert-Equal $script:Writes.Count 5
        Assert-Equal $script:Accounts['spray.user01'].Enabled $true
    }
    Run-Case 'An unfinished processing claim requires review' {
        $Id = Approve-Fixture
        Set-Content (Join-Path $script:State "processing/$Id.lock") ''
        Assert-Equal (Invoke-TestResponse).StatusCode 409
        Assert-Equal $script:Writes.Count 0
    }
    Run-Case 'A failed result cannot be automatically retried' {
        $Id = Approve-Fixture; $script:DisableFailure = 'spray.user03'
        $First = Invoke-TestResponse; $Second = Invoke-TestResponse
        Assert-Equal $Second.Body.status 'already_processed'
        Assert-Equal $Second.Body.success $false
        Assert-Equal $script:Writes.Count 5
    }
    Run-Case 'Approval requires a reason' {
        $Pending = Invoke-TestResponse
        Assert-Throws { New-SOARApproval -StateRoot $script:State -RequestId $Pending.Body.request_id -ApprovedBy 'reviewer' -Reason ' ' }
    }
    Run-Case 'Dry run does not consume an existing approval' {
        $Id = Approve-Fixture; $Preview = Invoke-TestResponse $true
        Assert-Equal $script:Writes.Count 0
        Assert-Equal (Invoke-TestResponse).Body.success $true
    }
    Write-Host "Response tests: $script:Passed passed, $script:Failed failed."
    if ($script:Failed -gt 0) { exit 1 }
}
finally { if (Test-Path $TestRoot) { Remove-Item $TestRoot -Recurse -Force } }
