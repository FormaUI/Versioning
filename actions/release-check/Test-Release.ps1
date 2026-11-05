#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
Holds a release tag to the release check.

.DESCRIPTION
Checks the tag the workflow runs for, with the repository checked out at its commit: the tag is named v and a version
by the version rules, it's annotated, and GitHub verifies its signature; its commit is the head commit of a merged
promotion pull request, and main's history holds it; the project's full-gate workflow passed on that commit on a push
to candidate; the tag's version is the one the commit declares; the changelog holds the version's entry, dated; and
the release's packages are held by the full-gate run or attached to the tag's GitHub release. The release's version
and the full-gate run are written to the step's outputs. Every result is written to the log and the job's summary,
and any check that fails fails the step.

.PARAMETER Repository
The repository, as owner/name.

.PARAMETER Tag
The release tag.

.PARAMETER GateWorkflow
The file name of the project's full-gate workflow, such as full.yml.

.PARAMETER VersionCommand
PowerShell that prints the package version the checked-out commit declares.

.PARAMETER Changelog
The changelog's path in the repository.

.PARAMETER PackagesArtifact
The name of the artifact the full-gate run keeps the packages it built in; empty for a project that publishes none.

.EXAMPLE
./Test-Release.ps1 -Repository FormaUI/Versioning -Tag v1.0.0-preview.1 -GateWorkflow ci.yml -VersionCommand '(Get-Content VERSION -Raw).Trim()'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Repository,
    [Parameter(Mandatory)] [string] $Tag,
    [Parameter(Mandatory)] [string] $GateWorkflow,
    [Parameter(Mandatory)] [string] $VersionCommand,
    [string] $Changelog = 'CHANGELOG.md',
    [string] $PackagesArtifact = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'Versioning.psm1') -Force

$results = [System.Collections.Generic.List[object]]::new()
$tagVersion = if ($Tag -cmatch '^v(.+)$') { $Matches[1] } else { '' }

# A checkout can leave the tag lightweight, so the tag object is fetched as the repository holds it.
$null = git fetch --quiet --force --no-tags origin "+refs/tags/$($Tag):refs/tags/$($Tag)" 2>&1
$tagProblems = [System.Collections.Generic.List[string]]::new()

if (-not (Test-VersionRule -Version $tagVersion)) {
    $tagProblems.Add("$Tag isn't v and a version by the version rules")
}

if ((git cat-file -t "refs/tags/$Tag" 2>&1) -cne 'tag') {
    $tagProblems.Add("$Tag is lightweight; a release tag is annotated")
}
else {
    $tagObject = Invoke-GitHubApi -Path "repos/$Repository/git/tags/$((git rev-parse "refs/tags/$Tag").Trim())"

    if (-not $tagObject.verification.verified) {
        $tagProblems.Add("GitHub doesn't verify $Tag's signature: $($tagObject.verification.reason)")
    }
}

$tagDetail = if ($tagProblems.Count -gt 0) { $tagProblems -join '; ' } else { "$Tag, annotated, with a signature GitHub verifies" }
$results.Add((New-CheckResult -Check 'Tag' -Holds ($tagProblems.Count -eq 0) -Detail $tagDetail))

$commit = (git rev-parse "refs/tags/$Tag^{commit}").Trim()
$commitProblems = [System.Collections.Generic.List[string]]::new()

if ((git rev-parse HEAD).Trim() -cne $commit) {
    $commitProblems.Add("the workflow checked out $((git rev-parse HEAD).Trim()); the check reads the tag's commit, $commit")
}

$null = git fetch --quiet --no-tags origin '+refs/heads/main:refs/remotes/origin/main' 2>&1
$null = git merge-base --is-ancestor $commit refs/remotes/origin/main 2>&1

if ($LASTEXITCODE -ne 0) {
    $commitProblems.Add("main's history doesn't hold $commit")
}

$promotion = @(Invoke-GitHubApi -Path "repos/$Repository/commits/$commit/pulls") | Where-Object {
    $_.merged_at -and $_.base.ref -ceq 'main' -and $_.head.ref -ceq 'candidate' -and $_.head.sha -ceq $commit -and
        $_.head.repo -and $_.head.repo.full_name -ceq $Repository
} | Select-Object -First 1

if (-not $promotion) {
    $commitProblems.Add("$commit isn't the head commit of a merged promotion pull request")
}

$commitDetail = if ($commitProblems.Count -gt 0) { $commitProblems -join '; ' } else { "$commit, promoted by pull request #$($promotion.number)" }
$results.Add((New-CheckResult -Check 'Commit' -Holds ($commitProblems.Count -eq 0) -Detail $commitDetail))

$run = Find-GateRun -Repository $Repository -Workflow $GateWorkflow -Commit $commit
$gateDetail = if ($run) { "$GateWorkflow passed on $commit, in run $($run.id)" } else { "$GateWorkflow hasn't passed on a push to candidate for $commit" }
$results.Add((New-CheckResult -Check 'Gate' -Holds ([bool]$run) -Detail $gateDetail))

$declared = (& ([scriptblock]::Create($VersionCommand)) | Out-String).Trim()
$versionDetail = if ($declared -ceq $tagVersion) { "$Tag names $declared, the version $commit declares" } else { "$Tag names $tagVersion, and $commit declares $declared" }
$results.Add((New-CheckResult -Check 'Version' -Holds ($declared -ceq $tagVersion) -Detail $versionDetail))

$entry = Get-ChangelogEntry -Path $Changelog -Version $tagVersion
$changelogDetail = if (-not $entry.Found) { "$Changelog doesn't hold an entry for $tagVersion" } elseif (-not $entry.Dated) { "The entry for $tagVersion isn't dated: $($entry.Line)" } else { "The entry for $tagVersion is dated: $($entry.Line)" }
$results.Add((New-CheckResult -Check 'Changelog' -Holds ($entry.Found -and $entry.Dated) -Detail $changelogDetail))

if (-not $PackagesArtifact) {
    $results.Add((New-CheckResult -Check 'Packages' -Holds $true -Detail 'The project publishes no package, so the tag is the release'))
}
else {
    $release = Invoke-GitHubApi -Path "repos/$Repository/releases/tags/$Tag" -AllowNotFound
    $attached = $release -and @($release.assets | ForEach-Object { $_.name }) -ccontains 'SHA256SUMS'
    $held = $run -and (Get-RunArtifact -Repository $Repository -RunId $run.id -Name $PackagesArtifact)

    $packagesDetail = if ($attached) {
        "An earlier run attached the packages to the GitHub release $Tag"
    }
    elseif ($held) {
        "Run $($run.id) holds the artifact $PackagesArtifact"
    }
    else {
        "Neither the full-gate run nor the GitHub release $Tag holds the packages"
    }

    $results.Add((New-CheckResult -Check 'Packages' -Holds ([bool]($attached -or $held)) -Detail $packagesDetail))
}

if ($env:GITHUB_OUTPUT) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "version=$tagVersion", "gate-run-id=$(if ($run) { $run.id })"
}

$failed = Write-CheckResult -Title 'The release check' -Result $results.ToArray()

if ($failed -gt 0) {
    exit 1
}
