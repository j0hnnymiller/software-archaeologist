#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(3, 20)][int]$Runs = 3,
    [string]$EvidenceParent = [System.IO.Path]::GetTempPath()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([string]$Directory, [string[]]$Arguments)
    $output = @(& git -C $Directory @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join "`n")"
    }
    return ($output -join "`n")
}

function Get-Snapshot {
    param([string]$Directory, [switch]$Initialized)
    $files = [System.Collections.Generic.SortedDictionary[string, string]]::new()
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($Directory)
    while ($pending.Count -gt 0) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            if ($item.Name -eq '.git') { continue }
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                throw "Cannot safely snapshot linked path: $($item.FullName)"
            }
            if ($item.PSIsContainer) {
                $pending.Push($item.FullName)
            } else {
                $files.Add([System.IO.Path]::GetRelativePath($Directory, $item.FullName),
                    (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash)
            }
        }
    }
    $snapshot = [ordered]@{
        head = Invoke-Git $Directory @('rev-parse', 'HEAD')
        status = Invoke-Git $Directory @('status', '--porcelain=v1', '--untracked-files=all', '--ignore-submodules=none')
        diff = Invoke-Git $Directory @('diff', '--binary', 'HEAD')
        files = $files
    }
    if ($Initialized) {
        $target = Join-Path $Directory 'target'
        $snapshot.targetHead = Invoke-Git $target @('rev-parse', 'HEAD')
        $snapshot.targetStatus = Invoke-Git $target @('status', '--porcelain=v1', '--untracked-files=all')
        $snapshot.targetDiff = Invoke-Git $target @('diff', '--binary', 'HEAD')
    }
    return ($snapshot | ConvertTo-Json -Depth 8)
}

function Assert-Trace {
    param([object[]]$Events)
    $agents = @($Events | Where-Object type -eq 'session.custom_agents_updated' |
        ForEach-Object { $_.data.agents } |
        Where-Object { $_.name -eq 'codebase-analyst' -and $_.source -eq 'project' })
    if ($agents.Count -eq 0) { throw 'No project codebase-analyst discovery event.' }
    foreach ($agent in $agents) {
        if ((@($agent.tools | Sort-Object) -join ',') -ne 'read,search') {
            throw 'Discovered agent does not have exactly read/search tools.'
        }
    }
    foreach ($event in $Events) {
        if ($event.type -eq 'session.error') { throw "CLI error: $($event.data | ConvertTo-Json -Compress)" }
        if ($event.type -eq 'session.info' -and $event.data.message -match 'Unknown tool name') {
            throw "CLI tool configuration error: $($event.data.message)"
        }
        if ($event.type -eq 'tool.execution_start' -and $event.data.toolName -notin @('view', 'glob', 'grep')) {
            throw "Unexpected tool execution: $($event.data.toolName)"
        }
        if ($event.type -eq 'tool.execution_complete' -and -not $event.data.success) {
            throw "Tool execution failed: $($event.data.toolCallId)"
        }
    }
    if (@($Events | Where-Object type -eq 'assistant.idle').Count -eq 0) {
        throw 'CLI trace has no completed assistant turn.'
    }
}

function Get-InspectedFiles {
    param([object[]]$Events, [string]$Directory)
    $successful = @{}
    foreach ($event in $Events | Where-Object type -eq 'tool.execution_complete') {
        if ($event.data.success) { $successful[$event.data.toolCallId] = $true }
    }
    foreach ($event in $Events | Where-Object type -eq 'tool.execution_start') {
        if ($event.data.toolName -eq 'view' -and $successful.ContainsKey($event.data.toolCallId)) {
            $path = [System.IO.Path]::GetFullPath($event.data.arguments.path, $Directory)
            if (Test-Path -LiteralPath $path -PathType Leaf) { $path }
        }
    }
}

function Assert-Report {
    param([string]$Report, [string]$Directory, [string[]]$InspectedFiles)
    $sections = @('Purpose', 'Structure and components', 'Entry points',
        'Dependencies and runtime', 'Build, test, and run commands', 'Uncertainties')
    $headings = @([regex]::Matches($Report, '(?m)^## (.+?)\r?$') |
        ForEach-Object { $_.Groups[1].Value })
    if (($headings -join '|') -cne ($sections -join '|')) {
        throw 'Report must contain all six required sections in order.'
    }
    $section = ''
    $counts = @{}
    $normalized = [regex]::Replace($Report.Trim(), '(?m)^(## [^\r\n]+)\r?$', "`$1`n")
    $blocks = [regex]::Split($normalized, '\r?\n(?=## |[-*] )|\r?\n\s*\r?\n')
    foreach ($block in $blocks) {
        $text = ($block.Trim() -replace '\r?\n', ' ').Trim()
        if (-not $text) { continue }
        if ($text -match '^## (.+)$') {
            $section = $Matches[1]
            continue
        }
        if ($section -eq 'Uncertainties' -and $text -eq 'No hypotheses identified.') {
            $counts[$section] = 1
            continue
        }
        $label = if ($section -eq 'Uncertainties') { 'Hypothesis' } else { 'Observed' }
        if ($text -notmatch "^[-*] \*\*${label}:\*\* .+ \(([^()]+)\)\.?$") {
            throw "Unlabeled, uncited, or unexpected report text: $text"
        }
        $citations = $Matches[1] -split ',\s*'
        foreach ($citation in $citations) {
            $relative = $citation.Trim().Trim('`') -replace '/', '\'
            if ($relative -notmatch '^target\\' -or $relative -match '(^|\\)\.\.(\\|$)|:\d') {
                throw "Invalid target citation: $citation"
            }
            $full = [System.IO.Path]::GetFullPath($relative, $Directory)
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Missing cited file: $citation" }
            if ($full -notin $InspectedFiles) { throw "Cited file has no successful view evidence: $citation" }
        }
        if (-not $counts.ContainsKey($section)) { $counts[$section] = 0 }
        $counts[$section]++
    }
    foreach ($required in $sections) {
        if (-not $counts.ContainsKey($required)) { throw "Empty section: $required" }
    }
}

function Assert-MissingReport {
    param([string]$Report)
    if ($Report -notmatch 'git submodule update --init --recursive' -or
        $Report -notmatch '(?i)missing|empty|not initialized|uninitialized|not available|not populated') {
        throw 'Missing-target report must identify the unavailable target and initialization command.'
    }
    if ($Report -match '(?m)^## (Purpose|Structure and components|Entry points|Dependencies and runtime|Build, test, and run commands)|\*\*(Observed|Hypothesis):\*\*') {
        throw 'Missing-target report contains overview findings.'
    }
}

function Invoke-Overview {
    param([string]$Directory, [string]$Prefix, [switch]$Initialized)
    $before = Get-Snapshot $Directory -Initialized:$Initialized
    Set-Content -LiteralPath "$Prefix.before.json" -Value $before
    $arguments = @('--agent', 'codebase-analyst', '--prompt',
        'Provide the required bounded overview of target using the workspace evidence rules.',
        '--trust-folder', '--allow-tool', 'read', '--allow-tool', 'search',
        '--deny-tool', 'shell', '--deny-tool', 'write',
        '--available-tools', 'view', 'glob', 'grep',
        '--disable-builtin-mcps', '--output-format', 'json', '--stream', 'off')
    $arguments | ConvertTo-Json | Set-Content -LiteralPath "$Prefix.arguments.json"
    Push-Location $Directory
    try {
        & copilot @arguments 1> "$Prefix.jsonl" 2> "$Prefix.stderr.txt"
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
        $after = Get-Snapshot $Directory -Initialized:$Initialized
        Set-Content -LiteralPath "$Prefix.after.json" -Value $after
        if ($before -cne $after) { throw "Read-only check failed: inspect $Prefix.before.json and $Prefix.after.json" }
    }
    if ($code -ne 0) { throw "Copilot exited $code. Inspect $Prefix.stderr.txt" }
    $events = @(Get-Content -LiteralPath "$Prefix.jsonl" | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-Trace $events
    $messages = @($events | Where-Object type -eq 'assistant.message')
    if ($messages.Count -eq 0) { throw 'No assistant report in CLI trace.' }
    $report = [string]$messages[-1].data.content
    Set-Content -LiteralPath "$Prefix.report.md" -Value $report
    if ($Initialized) {
        Assert-Report $report $Directory @(Get-InspectedFiles $events $Directory)
    } else {
        Assert-MissingReport $report
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$evidence = $null
$results = [ordered]@{
    status = 'failed'
    started = [DateTimeOffset]::UtcNow.ToString('o')
    checks = [System.Collections.Generic.List[object]]::new()
    manualReview = @('Claim support and uncertainty quality across reports',
        'Missing-target response contains no invented details',
        'VS Code Chat discovery and invocation', 'Unfamiliar-user onboarding')
}
try {
    Get-Command git, copilot -ErrorAction Stop | Out-Null
    $parent = [System.IO.Path]::GetFullPath($EvidenceParent)
    $rootPrefix = $root.TrimEnd('\') + '\'
    if ($parent -eq $root -or $parent.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'EvidenceParent must be outside the working repository.'
    }
    $evidence = Join-Path $parent ("verify-poc-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $evidence | Out-Null
    Write-Host "Evidence: $evidence"
    $results.revision = Invoke-Git $root @('rev-parse', 'HEAD')
    $version = @(& copilot --version 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Cannot query Copilot version: $version" }
    $results.cliVersion = $version -join "`n"
    foreach ($path in @('.github/agents/codebase-analyst.agent.md',
            '.github/instructions/codebase-analysis.instructions.md', '.gitmodules')) {
        $null = Invoke-Git $root @('cat-file', '-e', "HEAD:$path")
        if (Invoke-Git $root @('diff', 'HEAD', '--', $path)) {
            throw "Uncommitted verification input: $path. Runner tests committed HEAD only."
        }
    }
    $initialized = Join-Path $evidence 'initialized'
    $missing = Join-Path $evidence 'missing'
    $null = Invoke-Git $root @('clone', '--quiet', '--no-hardlinks', '--no-local', '--', $root, $initialized)
    $null = Invoke-Git $initialized @('checkout', '--quiet', '--detach', $results.revision)
    $null = Invoke-Git $initialized @('submodule', 'update', '--init', '--recursive')
    $pinLine = Invoke-Git $initialized @('ls-tree', 'HEAD', '--', 'target')
    if ($pinLine -notmatch '^160000 commit ([0-9a-f]+)\s+target$') { throw 'HEAD does not pin a target submodule.' }
    $results.targetRevision = $Matches[1]
    if ((Invoke-Git (Join-Path $initialized 'target') @('rev-parse', 'HEAD')) -ne $results.targetRevision) {
        throw 'Initialized target does not match pinned commit.'
    }
    $results.checks.Add(@{ name = 'clean recursive setup and pinned target'; status = 'pass' })
    for ($run = 1; $run -le $Runs; $run++) {
        $prefix = Join-Path $evidence "overview-$run"
        Invoke-Overview $initialized $prefix -Initialized
        $results.checks.Add(@{ name = "overview-$run structure, citations, tools, unchanged state"; status = 'pass' })
    }
    $null = Invoke-Git $root @('clone', '--quiet', '--no-hardlinks', '--no-local', '--', $root, $missing)
    $null = Invoke-Git $missing @('checkout', '--quiet', '--detach', $results.revision)
    $submoduleStatus = Invoke-Git $missing @('submodule', 'status', '--', 'target')
    if ($submoduleStatus -notmatch '^-') { throw 'Missing-target fixture is unexpectedly initialized.' }
    Invoke-Overview $missing (Join-Path $evidence 'missing-target')
    $results.checks.Add(@{ name = 'missing target response and unchanged state'; status = 'pass' })
    $results.status = 'automated checks passed; manual review pending'
} catch {
    $results.error = $_.Exception.Message
    [Console]::Error.WriteLine($results.error)
} finally {
    $results.ended = [DateTimeOffset]::UtcNow.ToString('o')
    if ($evidence) {
        $results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'results.json')
    }
}
if ($results.status -eq 'failed') { exit 1 }
Write-Host $results.status
