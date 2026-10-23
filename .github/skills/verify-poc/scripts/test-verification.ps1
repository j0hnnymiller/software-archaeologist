#requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'verify-poc.ps1')

function Assert-Rejected {
    param([string]$Name, [scriptblock]$Check)
    $rejected = $false
    try { & $Check } catch { $rejected = $true }
    if (-not $rejected) { throw "Expected rejection: $Name" }
    Write-Host "PASS: $Name"
}

$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("verify-poc-test-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $fixture 'target') | Out-Null
    $source = Join-Path $fixture 'target\README.md'
    Set-Content -LiteralPath $source -Value 'Synthetic source for verifier tests.'
    $report = @'
## Purpose
- **Observed:** Sample project. (target/README.md)
## Structure and components
- **Observed:** Sample structure. (target/README.md)
## Entry points
- **Observed:** Sample entry. (target/README.md)
## Dependencies and runtime
- **Observed:** Sample runtime. (target/README.md)
## Build, test, and run commands
- **Observed:** Sample command. (target/README.md)
## Uncertainties
No hypotheses identified.
'@
    Assert-Report $report $fixture @($source)
    Write-Host 'PASS: valid report with slash-separated citations'
    Assert-Report ($report.Replace('target/', 'target\')) $fixture @($source)
    Write-Host 'PASS: backslash-separated citations'
    Assert-Report ($report.Replace('No hypotheses identified.',
        '- **Hypothesis:** Sample interpretation. (target/README.md)')) $fixture @($source)
    Write-Host 'PASS: cited hypothesis'
    Assert-Rejected 'missing section' { Assert-Report ($report.Replace('## Purpose', '## Other')) $fixture @($source) }
    Assert-Rejected 'unlabeled claim' { Assert-Report ($report.Replace('**Observed:** Sample project.', 'Sample project.')) $fixture @($source) }
    Assert-Rejected 'uncited prose' { Assert-Report ($report + "`n`nInvented details.") $fixture @($source) }
    Assert-Rejected 'nonexistent citation' { Assert-Report ($report.Replace('README.md', 'absent.md')) $fixture @($source) }
    Assert-Rejected 'uninspected citation' { Assert-Report $report $fixture @() }
    Assert-Rejected 'citation traversal' { Assert-Report ($report.Replace('target/README.md', 'target/../README.md')) $fixture @($source) }
    Assert-Rejected 'line-number citation' { Assert-Report ($report.Replace('README.md', 'README.md:12')) $fixture @($source) }
    Assert-Rejected 'empty section' { Assert-Report ($report.Replace('- **Observed:** Sample entry. (target/README.md)', '')) $fixture @($source) }
    Assert-MissingReport 'The target is uninitialized. Run git submodule update --init --recursive.'
    Write-Host 'PASS: missing-target response'
    Assert-Rejected 'missing recovery command' { Assert-MissingReport 'The target is empty.' }
    Assert-Rejected 'missing-target overview' { Assert-MissingReport ("The target is empty. git submodule update --init --recursive`n" + $report) }

    $events = @(
        [pscustomobject]@{ type = 'session.custom_agents_updated'; data = [pscustomobject]@{
            agents = @([pscustomobject]@{ name = 'codebase-analyst'; source = 'project'; tools = @('read', 'search') })
        } },
        [pscustomobject]@{ type = 'tool.execution_start'; data = [pscustomobject]@{
            toolName = 'view'; toolCallId = 'read-1'; arguments = [pscustomobject]@{ path = $source }
        } },
        [pscustomobject]@{ type = 'tool.execution_complete'; data = [pscustomobject]@{
            toolCallId = 'read-1'; success = $true
        } },
        [pscustomobject]@{ type = 'assistant.idle'; data = [pscustomobject]@{} }
    )
    Assert-Trace $events
    if (@(Get-InspectedFiles $events $fixture) -notcontains $source) { throw 'Successful view was not recorded.' }
    Write-Host 'PASS: discovery, allowed tools, completed turn, successful read'
    Assert-Rejected 'no project agent discovery' { Assert-Trace @($events | Where-Object type -ne 'session.custom_agents_updated') }
    Assert-Rejected 'incomplete CLI turn' { Assert-Trace @($events | Where-Object type -ne 'assistant.idle') }
    $events[1].data.toolName = 'powershell'
    Assert-Rejected 'unexpected shell tool' { Assert-Trace $events }
    $events[1].data.toolName = 'view'
    $events[2].data.success = $false
    Assert-Rejected 'failed read tool' { Assert-Trace $events }
    if (@(Get-InspectedFiles $events $fixture).Count -ne 0) { throw 'Failed read counted as inspected.' }
    Write-Host 'PASS: failed read excluded from citation evidence'
    $events[2].data.success = $true
    $events[0].data.agents[0].tools = @('read', 'search', 'execute')
    Assert-Rejected 'agent tool scope broadened' { Assert-Trace $events }

    $null = Invoke-Git $fixture @('init', '--quiet')
    $null = Invoke-Git $fixture @('-c', 'user.name=Verifier Test', '-c',
        'user.email=verifier-test@example.invalid', 'commit', '--quiet', '--allow-empty', '-m', 'Synthetic fixture')
    $before = Get-Snapshot $fixture
    if ($before -cne (Get-Snapshot $fixture)) { throw 'Snapshot is not stable.' }
    Set-Content -LiteralPath $source -Value 'Changed content.'
    if ($before -ceq (Get-Snapshot $fixture)) { throw 'Snapshot missed file mutation.' }
    Write-Host 'PASS: stable snapshots and untracked content mutation detection'
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
Write-Host 'All verifier regression checks passed.'
