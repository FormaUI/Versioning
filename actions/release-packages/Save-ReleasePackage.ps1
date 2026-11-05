#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
Saves a release's packages, as its GitHub release holds them, into a directory to publish from.

.DESCRIPTION
The first run for a tag takes the packages the full-gate run built, attaches them to the tag's GitHub release with a
SHA256SUMS file naming each package's digest, the digests last, and saves what the release then holds. A later run
for the same tag saves the attached packages again; a release whose digests were never attached is attached afresh
from the full-gate run. Every saved package is checked against its digest, and the directory is written to the
step's outputs.

.PARAMETER Repository
The repository, as owner/name.

.PARAMETER Tag
The release tag.

.PARAMETER GateRunId
The full-gate run the release check found, which holds the packages it built.

.PARAMETER PackagesArtifact
The name of the artifact the full-gate run keeps the packages in.

.PARAMETER Directory
The directory the packages are saved in.

.PARAMETER Name
The project's name, which titles the GitHub release with the version.

.PARAMETER Changelog
The changelog's path in the repository, which the GitHub release links to at the tag.

.EXAMPLE
./Save-ReleasePackage.ps1 -Repository FormaUI/Forma -Tag v1.0.0-preview.1 -GateRunId 123 -PackagesArtifact packages -Directory release -Name Forma
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Repository,
    [Parameter(Mandatory)] [string] $Tag,
    [Parameter(Mandatory)] [string] $GateRunId,
    [Parameter(Mandatory)] [string] $PackagesArtifact,
    [Parameter(Mandatory)] [string] $Directory,
    [Parameter(Mandatory)] [string] $Name,
    [string] $Changelog = 'CHANGELOG.md'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'Versioning.psm1') -Force

function Invoke-GitHubCli {
    param([Parameter(Mandatory)] [string[]] $Argument)

    $output = gh @Argument 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "gh $($Argument -join ' ') failed: $($output -join "`n")"
    }
}

$version = $Tag -replace '^v', ''
$release = Invoke-GitHubApi -Path "repos/$Repository/releases/tags/$Tag" -AllowNotFound
$attached = $release -and @($release.assets | ForEach-Object { $_.name }) -ccontains 'SHA256SUMS'

if (-not $attached) {
    $staging = Join-Path ([System.IO.Path]::GetTempPath()) "release-packages-$([guid]::NewGuid().ToString('N'))"
    Save-RunArtifact -Repository $Repository -RunId $GateRunId -Name $PackagesArtifact -Directory $staging
    $files = @(Get-ChildItem -LiteralPath $staging -File -Recurse)

    if ($files.Count -eq 0) {
        throw "The artifact $PackagesArtifact of run $GateRunId holds no file."
    }

    $digests = Join-Path $staging 'SHA256SUMS'
    New-DigestFile -Directory $staging -Path $digests

    if (-not $release) {
        $notes = "What $Name $version changed is in the [changelog](https://github.com/$Repository/blob/$Tag/$Changelog)."
        $prerelease = if ($version.Contains('-')) { '--prerelease' } else { '--latest' }
        Invoke-GitHubCli -Argument 'release', 'create', $Tag, '--repo', $Repository, '--verify-tag', '--title', "$Name $version", '--notes', $notes, $prerelease
    }
    else {
        # A release whose digests were never attached published nothing, so what it holds is attached again.
        foreach ($asset in $release.assets) {
            Invoke-GitHubCli -Argument 'api', '--method', 'DELETE', "repos/$Repository/releases/assets/$($asset.id)"
        }
    }

    Invoke-GitHubCli -Argument (@('release', 'upload', $Tag, '--repo', $Repository) + $files.FullName)
    Invoke-GitHubCli -Argument 'release', 'upload', $Tag, '--repo', $Repository, $digests
}

$null = New-Item -ItemType Directory -Path $Directory -Force
Invoke-GitHubCli -Argument 'release', 'download', $Tag, '--repo', $Repository, '--dir', $Directory, '--clobber'
$problems = @(Test-DigestFile -Directory $Directory)

if ($problems.Count -gt 0) {
    throw "The packages attached to $Tag don't match their digests: $($problems -join '; ')."
}

$saved = @(Get-ChildItem -LiteralPath $Directory -File | Where-Object { $_.Name -cne 'SHA256SUMS' })
Write-Host "Saved $($saved.Count) packages of $Tag to $Directory, each matching its digest."

if ($env:GITHUB_OUTPUT) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "directory=$((Resolve-Path -LiteralPath $Directory).Path)"
}
