#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
Publishes a release's saved packages to a feed, in dependency order, past what the feed already holds.

.DESCRIPTION
Reads the packages release-packages saved, checked against their digests, and publishes each after the packages of
the release it depends on. A NuGet package is pushed to the NuGet feed named, with its symbols where the feed takes
them, and a push the feed already holds is skipped; an npm package is published to the npm registry under the
dist-tag of its stage, latest for a stable release and preview or rc for a pre-release, unless the registry holds it.

.PARAMETER Directory
The directory release-packages saved the packages in.

.PARAMETER NuGetSource
The NuGet feed's address; empty publishes no NuGet package.

.PARAMETER NuGetApiKey
The NuGet feed's key.

.PARAMETER NuGetSymbols
Whether the NuGet feed takes symbols packages beside the packages, as nuget.org does.

.PARAMETER Npm
Whether the npm packages are published to the npm registry.

.EXAMPLE
./Publish-ReleasePackage.ps1 -Directory release-packages -NuGetSource https://api.nuget.org/v3/index.json -NuGetApiKey $key
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $Directory,
    [string] $NuGetSource = '',
    [string] $NuGetApiKey = '',
    [bool] $NuGetSymbols = $true,
    [bool] $Npm = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'Versioning.psm1') -Force

$problems = @(Test-DigestFile -Directory $Directory)

if ($problems.Count -gt 0) {
    throw "The packages in $Directory don't match their digests: $($problems -join '; ')."
}

$packages = @(Get-PublicationOrder -Package @(Get-PackageInventory -Directory $Directory))
$nugetPackages = @($packages | Where-Object { $_.Ecosystem -ceq 'NuGet' })
$npmPackages = @($packages | Where-Object { $_.Ecosystem -ceq 'npm' })

if ($nugetPackages.Count -gt 0 -and $NuGetSource) {
    if (-not $NuGetApiKey) {
        throw "Publishing to $NuGetSource takes its key."
    }

    foreach ($package in $nugetPackages) {
        if ($PSCmdlet.ShouldProcess($NuGetSource, "Push $($package.Id) $($package.Version)")) {
            $arguments = @('nuget', 'push', $package.Path, '--source', $NuGetSource, '--api-key', $NuGetApiKey, '--skip-duplicate')

            if (-not $NuGetSymbols) {
                $arguments += '--no-symbols'
            }

            $output = dotnet @arguments 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "Pushing $($package.Id) $($package.Version) to $NuGetSource failed: $($output -join "`n")"
            }

            # A feed answers a version it holds with a conflict, which skipping duplicates turns into a warning.
            if (($output -join "`n") -match '(?i)\bconflict\b|already exists') {
                Write-Host "$NuGetSource already holds $($package.Id) $($package.Version)"
            }
            else {
                Write-Host "Pushed $($package.Id) $($package.Version) to $NuGetSource"
            }
        }
    }
}

if ($npmPackages.Count -gt 0 -and $Npm) {
    foreach ($package in $npmPackages) {
        if (Test-FeedVersion -Ecosystem npm -Id $package.Id -Version $package.Version) {
            Write-Host "The npm registry already holds $($package.Id) $($package.Version)"
            continue
        }

        $tag = if ($package.Version -cmatch '-(preview|rc)\.') { $Matches[1] } else { 'latest' }

        if ($PSCmdlet.ShouldProcess('the npm registry', "Publish $($package.Id) $($package.Version) under $tag")) {
            $output = npm publish $package.Path --tag $tag --access public 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "Publishing $($package.Id) $($package.Version) to the npm registry failed: $($output -join "`n")"
            }

            Write-Host "Published $($package.Id) $($package.Version) to the npm registry under $tag"
        }
    }
}
