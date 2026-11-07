#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
Releases a project's candidate: promotes it to main and pushes its signed release tag.

.DESCRIPTION
The maintainer runs it once they've decided to release, in a clone of the project, from a checkout of a released
Versioning tag outside that clone, so what's being released can't change what the command does. It reads nothing from
the candidate but text, and runs none of its code.

Before anything is pushed, it holds the release to every rule:

- The promotion pull request from candidate into main has the candidate's commit at its head, open with its promotion
  check passed, or merged.
- The project's full-gate workflow passed on that commit on a push to candidate.
- The project's release workflow at that commit names the release check's settings, which the command reads as text.
- The changelog's newest entry at that commit names the version being released, dated. The promotion check, which ran
  on that commit, holds the version the commit declares to a dated entry above every release, so the tag names the
  version the commit declares.
- The full-gate run still holds the packages, for a project that publishes them.

It then signs the tag in the clone and verifies its signature, so a signature that fails pushes nothing, and pushes
main and the tag in one atomic push, so both land or neither does. A release that stopped partway resumes: a signed tag
the clone already holds for the commit is pushed as it is, and main already at the commit isn't pushed again. A
release whose tag is pushed, with main at its commit, is reported done.

.PARAMETER Repository
The project's repository, as owner/name, whose name the tag's message carries.

.PARAMETER Version
The version being released, which the tag is named for.

.PARAMETER Path
The clone of the project the tag is signed in and pushed from.

.PARAMETER ReleaseWorkflow
The file name of the project's release workflow, which calls the release check.

.PARAMETER PromotionWorkflow
The file name of the project's promotion workflow, which runs the promotion check on the pull request.

.EXAMPLE
pwsh -NoProfile -File ~/.versioning/v1.0.0-preview.5/commands/New-Release.ps1 -Repository FormaUI/Forma -Version 1.0.0-preview.4 -Path ~/Projects/formaui-net
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [ValidatePattern('^[\w.-]+/[\w.-]+$')] [string] $Repository,
    [Parameter(Mandatory)] [string] $Version,
    [string] $Path = (Get-Location).Path,
    [string] $ReleaseWorkflow = 'release.yml',
    [string] $PromotionWorkflow = 'promotion.yml'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'actions' 'Versioning.psm1') -Force

# Runs git in the clone and returns what it wrote and its code.
function Invoke-Git {
    param([Parameter(Mandatory)] [string[]] $Arguments)

    $output = & git -C $Path @Arguments 2>&1
    [pscustomobject]@{ Code = $LASTEXITCODE; Text = (($output | ForEach-Object { "$_" }) -join "`n").Trim() }
}

if (-not (Test-VersionRule -Version $Version)) {
    throw "$Version isn't a version by the version rules."
}

$tag = "v$Version"
$owner, $name = $Repository -split '/'
$origin = Invoke-Git @('remote', 'get-url', 'origin')

if ($origin.Code -ne 0 -or $origin.Text -notmatch "github\.com[:/]$([regex]::Escape($Repository))(\.git)?$") {
    throw "$Path isn't a clone of $Repository; its origin is '$($origin.Text)'."
}

$fetched = Invoke-Git @('fetch', '--quiet', '--no-tags', 'origin', '+refs/heads/main:refs/remotes/origin/main', '+refs/heads/candidate:refs/remotes/origin/candidate')

if ($fetched.Code -ne 0) {
    throw "Fetching main and candidate failed: $($fetched.Text)"
}

$candidate = (Invoke-Git @('rev-parse', 'refs/remotes/origin/candidate')).Text
$main = (Invoke-Git @('rev-parse', 'refs/remotes/origin/main')).Text
$mainIsBehind = (Invoke-Git @('merge-base', '--is-ancestor', $main, $candidate)).Code -eq 0

# The commit the pushed tag marks, peeled where it's annotated.
$pushedTag = ''
$listed = Invoke-Git @('ls-remote', 'origin', "refs/tags/$tag", "refs/tags/$tag^{}")

foreach ($line in ($listed.Text -split "`n" | Where-Object { $_ })) {
    $sha, $ref = $line -split "`t"

    if ($ref -ceq "refs/tags/$tag^{}" -or -not $pushedTag) {
        $pushedTag = $sha
    }
}

$cloned = Invoke-Git @('rev-parse', '--verify', '--quiet', "refs/tags/$tag^{commit}")
$clonedTag = if ($cloned.Code -eq 0) { $cloned.Text } else { '' }
$step = Get-ReleaseStep -Candidate $candidate -Main $main -MainIsBehind $mainIsBehind -PushedTag $pushedTag -ClonedTag $clonedTag

if ($step.Problem) {
    throw $step.Problem
}

if ($step.Steps.Count -eq 0) {
    Write-Host "$tag is released: main and the tag mark $candidate."
    return
}

$results = [System.Collections.Generic.List[object]]::new()

# The promotion: open with its check passed while main is behind, merged once main is at the candidate.
if ($main -cne $candidate) {
    $pull = @(Invoke-GitHubApi -Path "repos/$Repository/pulls?state=open&base=main&head=$($owner):candidate&per_page=10") |
        Where-Object { $_.head.sha -ceq $candidate } | Select-Object -First 1
    $runs = (Invoke-GitHubApi -Path "repos/$Repository/actions/workflows/$PromotionWorkflow/runs?event=pull_request&head_sha=$candidate&per_page=100").workflow_runs
    $promotion = @($runs | Where-Object { $_.head_sha -ceq $candidate } | Sort-Object -Property id -Descending) | Select-Object -First 1
    $promoted = $pull -and $promotion -and $promotion.status -eq 'completed' -and $promotion.conclusion -eq 'success'
    $promotionDetail = if (-not $pull) {
        "No open pull request from candidate into main has $candidate at its head"
    }
    elseif (-not $promoted) {
        "Pull request #$($pull.number)'s promotion check hasn't passed on $candidate"
    }
    else {
        "Pull request #$($pull.number) has $candidate at its head, and its promotion check passed"
    }
}
else {
    $pull = @(Invoke-GitHubApi -Path "repos/$Repository/commits/$candidate/pulls") | Where-Object {
        $_.merged_at -and $_.base.ref -ceq 'main' -and $_.head.ref -ceq 'candidate' -and $_.head.sha -ceq $candidate
    } | Select-Object -First 1
    $promoted = [bool]$pull
    $promotionDetail = if ($promoted) { "Pull request #$($pull.number) promoted $candidate" } else { "No merged promotion pull request has $candidate at its head" }
}

$results.Add((New-CheckResult -Check 'Promotion' -Holds ([bool]$promoted) -Detail $promotionDetail))

# The candidate's tree, read as text.
$tree = Join-Path ([System.IO.Path]::GetTempPath()) "versioning-release-$([guid]::NewGuid().ToString('N'))"
# Reading the tree is no change, so a described run reads it too.
$null = New-Item -ItemType Directory -Path $tree -WhatIf:$false

try {
    $archive = Join-Path $tree 'tree.tar'
    $archived = Invoke-Git @('archive', '--format=tar', '-o', $archive, $candidate)

    if ($archived.Code -ne 0) {
        throw "Reading $candidate's tree failed: $($archived.Text)"
    }

    tar -xf $archive -C $tree

    if ($LASTEXITCODE -ne 0) {
        throw "Unpacking $candidate's tree failed."
    }

    $inputs = Get-ReleaseCheckInput -Path (Join-Path $tree '.github' 'workflows' $ReleaseWorkflow)

    if ($null -eq $inputs -or -not $inputs.Contains('gate-workflow')) {
        throw "$ReleaseWorkflow at $candidate calls no release check with a gate-workflow, so the release's rules can't be read."
    }

    $gateWorkflow = $inputs['gate-workflow']
    $changelog = if ($inputs.Contains('changelog') -and $inputs['changelog']) { $inputs['changelog'] } else { 'CHANGELOG.md' }
    $packagesArtifact = if ($inputs.Contains('packages-artifact')) { $inputs['packages-artifact'] } else { '' }

    $run = Find-GateRun -Repository $Repository -Workflow $gateWorkflow -Commit $candidate
    $gateDetail = if ($run) { "$gateWorkflow passed on $candidate, in run $($run.id)" } else { "$gateWorkflow hasn't passed on a push to candidate for $candidate" }
    $results.Add((New-CheckResult -Check 'Gate' -Holds ([bool]$run) -Detail $gateDetail))

    $changelogPath = Join-Path $tree $changelog
    $newest = @(Get-ChangelogVersion -Path $changelogPath) | Select-Object -First 1
    $entry = Get-ChangelogEntry -Path $changelogPath -Version $Version
    $isNewest = $newest -ceq $Version -and $entry.Found -and $entry.Dated
    $changelogDetail = if ($newest -cne $Version) {
        "$changelog's newest entry is $newest, not $Version"
    }
    elseif (-not $entry.Dated) {
        "The entry for $Version isn't dated: $($entry.Line)"
    }
    else {
        "$changelog's newest entry is $Version, dated: $($entry.Line)"
    }

    $results.Add((New-CheckResult -Check 'Changelog' -Holds $isNewest -Detail $changelogDetail))

    if (-not $packagesArtifact) {
        $results.Add((New-CheckResult -Check 'Packages' -Holds $true -Detail 'The project publishes no package'))
    }
    else {
        $held = $run -and (Get-RunArtifact -Repository $Repository -RunId $run.id -Name $packagesArtifact)
        $packagesDetail = if ($held) { "Run $($run.id) holds the artifact $packagesArtifact" } else { "The full-gate run doesn't hold the artifact $packagesArtifact" }
        $results.Add((New-CheckResult -Check 'Packages' -Holds ([bool]$held) -Detail $packagesDetail))
    }
}
finally {
    Remove-Item -LiteralPath $tree -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false
}

$failed = Write-CheckResult -Title "Releasing $tag at $candidate" -Result $results.ToArray()

if ($failed -gt 0) {
    throw 'The release holds to the rules only once every check holds. Nothing was signed or pushed.'
}

# The tag is signed first, so a signature that fails leaves nothing pushed.
if ($step.Steps -contains 'Sign') {
    if ($PSCmdlet.ShouldProcess("$candidate, in $Path", "Sign the tag $tag")) {
        $signed = Invoke-Git @('tag', '-s', $tag, $candidate, '-m', "$name $Version")

        if ($signed.Code -ne 0) {
            throw "Signing $tag failed, and nothing was pushed: $($signed.Text)"
        }
    }
}

if (-not $WhatIfPreference) {
    $verified = Invoke-Git @('tag', '-v', $tag)

    if ($verified.Code -ne 0 -or (Invoke-Git @('cat-file', '-t', "refs/tags/$tag")).Text -cne 'tag') {
        throw "$tag isn't an annotated tag with a signature that verifies, and nothing was pushed: $($verified.Text)"
    }
}

$refs = @(
    if ($step.Steps -contains 'Promote') { "$($candidate):refs/heads/main" }
    "refs/tags/$tag"
)

if ($PSCmdlet.ShouldProcess($Repository, "Push $($refs -join ' and ') in one atomic push")) {
    $pushed = Invoke-Git (@('push', '--atomic', 'origin') + $refs)

    if ($pushed.Code -ne 0) {
        throw "The atomic push failed, so neither main nor the tag moved: $($pushed.Text)"
    }

    Write-Host "$tag is pushed, with main at $candidate; the release workflow runs at https://github.com/$Repository/actions"
}
