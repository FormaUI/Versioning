#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
Holds a pull request into main to the promotion check.

.DESCRIPTION
Checks the pull request the workflow runs for, with the repository checked out at its head commit: it comes from
this repository's candidate, the project's full-gate workflow passed on its head commit on a push to candidate, the
version the head commit declares is a release version higher than every release before it and every feed lacks it,
the full-gate run still holds the packages it built, and the changelog holds the version's entry, dated. Every
result is written to the log and the job's summary, and any check that fails fails the step.

.PARAMETER Repository
The repository, as owner/name.

.PARAMETER GateWorkflow
The file name of the project's full-gate workflow, such as full.yml.

.PARAMETER VersionCommand
PowerShell that prints the package version the checked-out commit declares.

.PARAMETER Changelog
The changelog's path in the repository.

.PARAMETER PackagesArtifact
The name of the artifact the full-gate run keeps the packages it built in; empty for a project that publishes none.

.PARAMETER EventPath
The pull request event's payload.

.EXAMPLE
./Test-Promotion.ps1 -Repository FormaUI/Versioning -GateWorkflow ci.yml -VersionCommand '(Get-Content VERSION -Raw).Trim()'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Repository,
    [Parameter(Mandatory)] [string] $GateWorkflow,
    [Parameter(Mandatory)] [string] $VersionCommand,
    [string] $Changelog = 'CHANGELOG.md',
    [string] $PackagesArtifact = '',
    [string] $EventPath = $env:GITHUB_EVENT_PATH
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'Versioning.psm1') -Force

$pullRequest = (Get-Content -LiteralPath $EventPath -Raw | ConvertFrom-Json).pull_request
$head = $pullRequest.head.sha
$headRepository = if ($pullRequest.head.repo) { $pullRequest.head.repo.full_name } else { '' }
$results = [System.Collections.Generic.List[object]]::new()

$fromCandidate = $headRepository -ceq $Repository -and $pullRequest.head.ref -ceq 'candidate' -and $pullRequest.base.ref -ceq 'main'
$route = if ($headRepository -ceq $Repository -and $pullRequest.head.ref -ceq 'dev') {
    "fast-forward candidate to dev's commit and open the promotion from candidate"
}
else {
    'open this pull request against dev'
}

$sourceDetail = if ($fromCandidate) {
    "From $($pullRequest.head.label) into main"
}
else {
    "From $($pullRequest.head.label) into $($pullRequest.base.ref): main takes this repository's candidate alone, so $route"
}

$results.Add((New-CheckResult -Check 'Source' -Holds $fromCandidate -Detail $sourceDetail))

$checkedOut = (git rev-parse HEAD).Trim()

if ($checkedOut -cne $head) {
    $results.Add((New-CheckResult -Check 'Checkout' -Holds $false -Detail "The workflow checked out $checkedOut; the check reads the pull request's head commit, $head"))
}

$run = Find-GateRun -Repository $Repository -Workflow $GateWorkflow -Commit $head
$gateDetail = if ($run) { "$GateWorkflow passed on $head, in run $($run.id)" } else { "$GateWorkflow hasn't passed on a push to candidate for $head" }
$results.Add((New-CheckResult -Check 'Gate' -Holds ([bool]$run) -Detail $gateDetail))

$version = (& ([scriptblock]::Create($VersionCommand)) | Out-String).Trim()
$highest = Get-HighestVersion -Version @(Get-ReleaseVersion -Repository $Repository)
$versionProblems = [System.Collections.Generic.List[string]]::new()

if (-not (Test-VersionRule -Version $version)) {
    $versionProblems.Add("$version isn't a version by the version rules")
}
elseif ($highest -and (Compare-Version -Left $version -Right $highest) -le 0) {
    $versionProblems.Add("$version isn't higher than the release $highest")
}

$packages = @()

if (-not $PackagesArtifact) {
    $results.Add((New-CheckResult -Check 'Packages' -Holds $true -Detail 'The project publishes no package'))
}
elseif (-not $run) {
    $results.Add((New-CheckResult -Check 'Packages' -Holds $false -Detail 'The packages are read from the full-gate run, which has to pass first'))
}
elseif (-not (Get-RunArtifact -Repository $Repository -RunId $run.id -Name $PackagesArtifact)) {
    $results.Add((New-CheckResult -Check 'Packages' -Holds $false -Detail "Run $($run.id) doesn't hold the artifact $PackagesArtifact; run the full gate on the candidate again"))
}
else {
    $staging = Join-Path ([System.IO.Path]::GetTempPath()) "promotion-packages-$([guid]::NewGuid().ToString('N'))"
    Save-RunArtifact -Repository $Repository -RunId $run.id -Name $PackagesArtifact -Directory $staging
    $packages = @(Get-PackageInventory -Directory $staging)
    $mismatched = @($packages | Where-Object { $_.Version -cne $version })

    $packagesDetail = if ($packages.Count -eq 0) {
        "The artifact $PackagesArtifact holds no package"
    }
    elseif ($mismatched.Count -gt 0) {
        "Packages that don't carry $($version): $(($mismatched | ForEach-Object { "$($_.Id) $($_.Version)" }) -join ', ')"
    }
    else {
        "Run $($run.id) holds $($packages.Count) packages at $version"
    }

    $results.Add((New-CheckResult -Check 'Packages' -Holds ($packages.Count -gt 0 -and $mismatched.Count -eq 0) -Detail $packagesDetail))

    foreach ($package in $packages | Where-Object { Test-FeedVersion -Ecosystem $_.Ecosystem -Id $_.Id -Version $version }) {
        $versionProblems.Add("$($package.Ecosystem) already holds $($package.Id) $version")
    }
}

$versionDetail = if ($versionProblems.Count -gt 0) { $versionProblems -join '; ' } else { "$version, higher than $(if ($highest) { "the release $highest" } else { 'every release, as the first' })" }
$results.Insert($results.Count - 1, (New-CheckResult -Check 'Version' -Holds ($versionProblems.Count -eq 0) -Detail $versionDetail))

$entry = Get-ChangelogEntry -Path $Changelog -Version $version
$changelogDetail = if (-not $entry.Found) { "$Changelog doesn't hold an entry for $version" } elseif (-not $entry.Dated) { "The entry for $version isn't dated: $($entry.Line)" } else { "The entry for $version is dated: $($entry.Line)" }
$results.Add((New-CheckResult -Check 'Changelog' -Holds ($entry.Found -and $entry.Dated) -Detail $changelogDetail))

$failed = Write-CheckResult -Title 'The promotion check' -Result $results.ToArray()

if ($failed -gt 0) {
    exit 1
}
