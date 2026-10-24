#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path $PSScriptRoot -Parent) 'replace-target.ps1'
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("replace-target-tests-" + [guid]::NewGuid().ToString('N'))

function Invoke-Git {
    param([string]$Directory, [string[]]$Arguments)
    $output = @(& git -C $Directory @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join "`n")"
    }
    return ($output -join "`n")
}

function Commit-Fixture {
    param([string]$Directory)
    $null = Invoke-Git $Directory @('add', '--all')
    $null = Invoke-Git $Directory @('-c', 'user.name=Replacement Test', '-c',
        'user.email=replacement-test@example.invalid', 'commit', '--quiet', '-m', 'Fixture')
}

function Assert-Rejected {
    param([string]$Name, [scriptblock]$Action, [string]$Expected)
    $beforeHead = Invoke-Git $hostRepo @('rev-parse', 'HEAD')
    $beforeStatus = Invoke-Git $hostRepo @('status', '--porcelain=v1', '--untracked-files=all')
    $beforeModules = Get-Content -LiteralPath (Join-Path $hostRepo '.gitmodules') -Raw
    $message = $null
    try { & $Action } catch { $message = $_.Exception.Message }
    if (-not $message -or $message -notmatch $Expected) {
        throw "Expected rejection ($Name), got: $message"
    }
    if ($beforeHead -ne (Invoke-Git $hostRepo @('rev-parse', 'HEAD')) -or
        $beforeStatus -ne (Invoke-Git $hostRepo @('status', '--porcelain=v1', '--untracked-files=all')) -or
        $beforeModules -cne (Get-Content -LiteralPath (Join-Path $hostRepo '.gitmodules') -Raw)) {
        throw "Rejected operation mutated the repository: $Name"
    }
    Write-Host "PASS: $Name"
}

New-Item -ItemType Directory -Path $fixture | Out-Null
$originalTemp = $env:TEMP
$originalTmp = $env:TMP
$env:TEMP = $fixture
$env:TMP = $fixture
try {
    $oldRepo = Join-Path $fixture 'old source'
    $newRepo = Join-Path $fixture 'new source'
    $hostRepo = Join-Path $fixture 'host repository'
    foreach ($directory in @($oldRepo, $newRepo, $hostRepo)) {
        New-Item -ItemType Directory -Path $directory | Out-Null
        $null = Invoke-Git $directory @('init', '--quiet')
        Set-Content -LiteralPath (Join-Path $directory 'identity.txt') -Value $directory
        Set-Content -LiteralPath (Join-Path $directory '.gitignore') -Value 'ignored.txt'
        Commit-Fixture $directory
    }
    $null = Invoke-Git $hostRepo @('-c', 'protocol.file.allow=always', 'submodule',
        'add', '--quiet', '--name', 'original-target', '--', $oldRepo, 'target')
    $null = Invoke-Git $hostRepo @('-c', 'protocol.file.allow=always', 'submodule',
        'add', '--quiet', '--name', 'unrelated', '--', $newRepo, 'unrelated')
    Commit-Fixture $hostRepo
    $target = Join-Path $hostRepo 'target'
    $oldMetadata = Invoke-Git $target @('rev-parse', '--absolute-git-dir')
    $hostHead = Invoke-Git $hostRepo @('rev-parse', 'HEAD')
    $oldHead = Invoke-Git $target @('rev-parse', 'HEAD')
    $null = & $script -Url $newRepo -RepositoryRoot $hostRepo -WhatIf
    if ((Invoke-Git $hostRepo @('status', '--porcelain=v1')) -or
        (Invoke-Git $target @('rev-parse', 'HEAD')) -ne $oldHead) { throw 'WhatIf changed the repository.' }
    Write-Host 'PASS: WhatIf leaves target and index unchanged'

    Set-Content -LiteralPath (Join-Path $hostRepo 'untracked.txt') -Value 'save me'
    Assert-Rejected 'untracked host file' { & $script -Url $newRepo -RepositoryRoot $hostRepo } 'Commit or stash'
    Remove-Item -LiteralPath (Join-Path $hostRepo 'untracked.txt')
    Add-Content -LiteralPath (Join-Path $target 'identity.txt') -Value 'local edit'
    Assert-Rejected 'dirty target' { & $script -Url $newRepo -RepositoryRoot $hostRepo } 'Commit or stash'
    Set-Content -LiteralPath (Join-Path $target 'identity.txt') -Value $oldRepo
    Set-Content -LiteralPath (Join-Path $target 'ignored.txt') -Value 'save ignored data'
    Assert-Rejected 'ignored target file' { & $script -Url $newRepo -RepositoryRoot $hostRepo } 'ignored files'
    if (-not (Test-Path -LiteralPath (Join-Path $target 'ignored.txt'))) { throw 'Ignored data was lost.' }
    Remove-Item -LiteralPath (Join-Path $target 'ignored.txt')
    Assert-Rejected 'URL option injection' { & $script -Url '--upload-pack=bad' -RepositoryRoot $hostRepo } 'not a Git option'
    Assert-Rejected 'invalid remote preserves original target' {
        & $script -Url (Join-Path $fixture 'missing') -RepositoryRoot $hostRepo -WarningAction SilentlyContinue
    } 'failed:'
    $emptyRepo = Join-Path $fixture 'empty'
    New-Item -ItemType Directory -Path $emptyRepo | Out-Null
    $null = Invoke-Git $emptyRepo @('init', '--quiet')
    Assert-Rejected 'empty remote preserves original target' {
        & $script -Url $emptyRepo -RepositoryRoot $hostRepo -WarningAction SilentlyContinue
    } 'failed:'

    $null = Invoke-Git $target @('-c', 'protocol.file.allow=always', 'submodule',
        'add', '--quiet', '--', $newRepo, 'nested')
    Commit-Fixture $target
    Commit-Fixture $hostRepo
    $nestedFile = Join-Path $target 'nested\ignored.txt'
    Set-Content -LiteralPath $nestedFile -Value 'save nested ignored data'
    Assert-Rejected 'ignored nested-submodule file' {
        & $script -Url $newRepo -RepositoryRoot $hostRepo
    } 'ignored files'
    if (-not (Test-Path -LiteralPath $nestedFile)) { throw 'Nested ignored data was lost.' }
    Remove-Item -LiteralPath $nestedFile

    # Keep a local-only commit to prove the old object database survives replacement.
    Set-Content -LiteralPath (Join-Path $target 'local-only.txt') -Value 'recoverable'
    Commit-Fixture $target
    Commit-Fixture $hostRepo
    $hostHead = Invoke-Git $hostRepo @('rev-parse', 'HEAD')
    $localHead = Invoke-Git $target @('rev-parse', 'HEAD')
    & $script -Url $newRepo -RepositoryRoot $hostRepo
    if ((Invoke-Git $target @('rev-parse', 'HEAD')) -ne (Invoke-Git $newRepo @('rev-parse', 'HEAD'))) {
        throw 'Replacement checked out the wrong commit.'
    }
    if ((Invoke-Git $target @('remote', 'get-url', 'origin')) -ne $newRepo) { throw 'Wrong replacement origin.' }
    if ((Invoke-Git $hostRepo @('rev-parse', 'HEAD')) -ne $hostHead) { throw 'Script created a commit.' }
    if (-not (Test-Path -LiteralPath $oldMetadata)) { throw 'Old metadata was deleted.' }
    $null = Invoke-Git $oldMetadata @('cat-file', '-e', "$localHead^{commit}")
    if ((Invoke-Git $hostRepo @('diff', '--name-only')) -or
        (Invoke-Git $hostRepo @('diff', '--cached', '--name-only')) -ne ".gitmodules`ntarget") {
        throw 'Expected exactly the two staged replacement paths and no unstaged changes.'
    }
    $newKey = (Invoke-Git $hostRepo @('config', '--file', '.gitmodules',
        '--name-only', '--get-regexp', '^submodule\.target-.*\.url$')).Trim()
    if ((Invoke-Git $hostRepo @('config', '--file', '.gitmodules', '--get', $newKey)) -ne $newRepo) {
        throw 'Wrong .gitmodules URL.'
    }
    if (Test-Path -LiteralPath (Join-Path $target '.git') -PathType Container) { throw 'New Git directory was not absorbed.' }
    if ((Invoke-Git $hostRepo @('config', '--file', '.gitmodules', '--get', 'submodule.unrelated.url')) -ne $newRepo -or
        (Invoke-Git (Join-Path $hostRepo 'unrelated') @('rev-parse', 'HEAD')) -ne
        (Invoke-Git $newRepo @('rev-parse', 'HEAD'))) { throw 'Unrelated submodule changed.' }
    Write-Host 'PASS: replacement, staging, origin, absorbed metadata, and local-only history retention'
    Write-Host 'PASS: unrelated submodule is preserved'

    Commit-Fixture $hostRepo
    $null = Invoke-Git $hostRepo @('submodule', 'deinit', '--', 'target')
    & $script -Url $oldRepo -RepositoryRoot $hostRepo
    if ((Invoke-Git $target @('rev-parse', 'HEAD')) -ne $oldHead) { throw 'Uninitialized replacement failed.' }
    Write-Host 'PASS: uninitialized target replacement and repeated replacement'
} finally {
    $env:TEMP = $originalTemp
    $env:TMP = $originalTmp
    # Only remove this test's uniquely named synthetic repositories.
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
Write-Host 'All replacement tests passed.'
