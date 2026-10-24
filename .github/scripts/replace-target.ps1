#requires -Version 7.0
<#
.SYNOPSIS
Replaces the target submodule with a repository URL, leaving the change staged.
.EXAMPLE
.\.github\scripts\replace-target.ps1 -Url https://github.com/owner/repository.git
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Url,
    [string]$RepositoryRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
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

if ([string]::IsNullOrWhiteSpace($Url) -or $Url.StartsWith('-')) {
    throw 'Url must be a repository URL or path, not a Git option.'
}
$root = (Resolve-Path -LiteralPath $RepositoryRoot).ProviderPath
$gitRoot = Invoke-Git $root @('rev-parse', '--show-toplevel')
if ([System.IO.Path]::GetFullPath($gitRoot) -ne $root) {
    throw 'RepositoryRoot must be the top-level working directory.'
}
$modulesFile = Join-Path $root '.gitmodules'
$entries = (Invoke-Git $root @('config', '--file', $modulesFile,
    '--get-regexp', '^submodule\..*\.path$')) -split "`n"
$targetEntries = @($entries | Where-Object { ($_ -split ' ', 2)[1] -eq 'target' })
if ($targetEntries.Count -ne 1) {
    throw 'Expected exactly one submodule configured at target.'
}
$indexEntry = Invoke-Git $root @('ls-files', '--stage', '--', 'target')
if ($indexEntry -notmatch '^160000 [0-9a-f]+ 0\s+target$') {
    throw 'target must be a tracked, unconflicted submodule.'
}
$status = Invoke-Git $root @('status', '--porcelain=v1', '--untracked-files=all',
    '--ignore-submodules=none')
if ($status) {
    throw "Commit or stash working-tree changes before replacing target:`n$status"
}

$target = Join-Path $root 'target'
$oldGitDirectory = $null
if (Test-Path -LiteralPath (Join-Path $target '.git')) {
    $targetStatus = Invoke-Git $target @('status', '--porcelain=v1',
        '--untracked-files=all', '--ignored', '--ignore-submodules=none')
    $nestedStatus = Invoke-Git $target @('submodule', 'foreach', '--quiet', '--recursive',
        'git status --porcelain=v1 --untracked-files=all --ignored --ignore-submodules=none')
    if ($targetStatus -or $nestedStatus) {
        throw "target or a nested submodule contains local changes, untracked files, or ignored files. Move or save them first.`n$targetStatus`n$nestedStatus"
    }
    $oldGitDirectory = Invoke-Git $target @('rev-parse', '--absolute-git-dir')
    if (Test-Path -LiteralPath (Join-Path $target '.git') -PathType Container) {
        throw 'target has an embedded .git directory. Run git submodule absorbgitdirs -- target first.'
    }
} elseif ((Test-Path -LiteralPath $target) -and
    @((Get-ChildItem -LiteralPath $target -Force)).Count -gt 0) {
    throw 'Uninitialized target contains files. Move or save them first.'
}

if (-not $PSCmdlet.ShouldProcess($root, "Replace target submodule with $Url and stage the change")) {
    return
}

$prepared = Join-Path ([System.IO.Path]::GetTempPath()) ("replacement-target-" + [guid]::NewGuid().ToString('N'))
$newName = 'target-' + [guid]::NewGuid().ToString('N')
try {
    # Finish network access before removing the existing checkout.
    $null = Invoke-Git $root @('clone', '--no-hardlinks', '--', $Url, $prepared)
    $null = Invoke-Git $prepared @('rev-parse', '--verify', 'HEAD')
    $null = Invoke-Git $root @('submodule', 'deinit', '--', 'target')
    $null = Invoke-Git $root @('rm', '--', 'target')
    if (Test-Path -LiteralPath $target) {
        [System.IO.Directory]::Delete($target)
    }
    Move-Item -LiteralPath $prepared -Destination $target
    # A fresh name avoids reusing the old repository's cached objects or origin.
    $null = Invoke-Git $root @('submodule', 'add', '--name', $newName, '--', $Url, 'target')
    $null = Invoke-Git $root @('submodule', 'absorbgitdirs', '--', 'target')
} catch {
    Write-Warning "Replacement failed. Inspect git status before retrying; changes are not automatically rolled back. Any prepared clone remains at $prepared or $target."
    if ($oldGitDirectory) {
        Write-Warning "The previous submodule's Git metadata is retained at $oldGitDirectory."
    }
    throw
}
Write-Host 'Replaced target. The .gitmodules and target changes are staged; no commit was created.'
if ($oldGitDirectory) {
    Write-Host "Previous Git metadata retained for recovery: $oldGitDirectory"
}
Write-Host 'Nested submodules in the new target are not initialized. If needed, run git submodule update --init --recursive -- target.'
