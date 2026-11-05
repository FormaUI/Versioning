#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
Runs the cases of the functions the checks share.

.DESCRIPTION
Each case runs the functions for real against values or files made for it, and names what it found wrong. The script
writes each case's result and returns one line for each problem, so the gate can fail on them.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'actions' 'Versioning.psm1') -Force

$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) "versioning-tests-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $scratch

$cases = [ordered]@{
    'a version the version rules allow passes, and any other fails' = {
        foreach ($version in '1.0.0', '1.0.0-preview.1', '1.0.0-rc.10', '10.20.30', '2.0.0-preview.12') {
            if (-not (Test-VersionRule -Version $version)) { "$version was refused" }
        }

        foreach ($version in '', '1.0', '01.0.0', 'v1.0.0', '1.0.0-beta.1', '1.0.0-preview10', '1.0.0-preview.0', '1.0.0-Preview.1', '1.0.0-preview.1+build') {
            if (Test-VersionRule -Version $version) { "$version was allowed" }
        }
    }

    'versions compare by Semantic Versioning precedence' = {
        $ascending = '1.0.0-alpha', '1.0.0-alpha.1', '1.0.0-alpha.beta', '1.0.0-beta', '1.0.0-beta.2', '1.0.0-beta.11',
        '1.0.0-preview.1', '1.0.0-preview.9', '1.0.0-preview.10', '1.0.0-rc.1', '1.0.0', '1.0.1', '1.1.0', '2.0.0-preview.1', '2.0.0'

        for ($index = 0; $index -lt $ascending.Count - 1; $index++) {
            $lower = $ascending[$index]
            $higher = $ascending[$index + 1]

            if ((Compare-Version -Left $lower -Right $higher) -ne -1) { "$lower didn't compare below $higher" }
            if ((Compare-Version -Left $higher -Right $lower) -ne 1) { "$higher didn't compare above $lower" }
        }

        if ((Compare-Version -Left '1.0.0-preview.1' -Right '1.0.0-preview.1') -ne 0) { 'a version didn''t compare equal to itself' }
        if ((Compare-Version -Left '1.0.0+build.5' -Right '1.0.0') -ne 0) { 'build metadata took part in precedence' }
    }

    'the highest of a set of versions is found, and an empty set has none' = {
        $highest = Get-HighestVersion -Version '1.0.0-preview.9', '1.0.0-preview.10', '1.0.0-beta.2'

        if ($highest -cne '1.0.0-preview.10') { "the highest was $highest" }
        if ($null -ne (Get-HighestVersion -Version @())) { 'an empty set had a highest version' }
    }

    'a changelog entry is found, and it''s dated only by a date' = {
        $path = Join-Path $scratch 'CHANGELOG.md'
        $text = @(
            '# Changelog', '', '<a id="v1-0-0-preview-3"></a>', '', '## `1.0.0-preview.3`', '',
            '*November 4, 2026 · language `1.0.0-preview.2` · definition format 38*', '', '- A change.', '',
            '## `1.0.0-preview.2`', '', '*Unreleased*', '', '## `1.0.0-preview.1`', '', '*November 5, 2026*', ''
        ) -join "`n"
        [System.IO.File]::WriteAllText($path, $text)

        $nexo = Get-ChangelogEntry -Path $path -Version '1.0.0-preview.3'
        $unreleased = Get-ChangelogEntry -Path $path -Version '1.0.0-preview.2'
        $dated = Get-ChangelogEntry -Path $path -Version '1.0.0-preview.1'
        $missing = Get-ChangelogEntry -Path $path -Version '1.0.0-rc.1'

        if (-not ($nexo.Found -and $nexo.Dated)) { 'an entry dated before the versions it names wasn''t dated' }
        if (-not $unreleased.Found -or $unreleased.Dated) { 'an unreleased entry was dated' }
        if (-not ($dated.Found -and $dated.Dated)) { 'a dated entry wasn''t dated' }
        if ($missing.Found) { 'a version the changelog lacks was found' }
        if ((Get-ChangelogEntry -Path (Join-Path $scratch 'none.md') -Version '1.0.0').Found) { 'a missing changelog held an entry' }
    }

    'a directory''s packages are read from the packages themselves' = {
        $directory = Join-Path $scratch 'packages'
        $null = New-Item -ItemType Directory -Path $directory

        $nuspec = '<?xml version="1.0"?><package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">' +
            '<metadata><id>Sample.Package</id><version>1.0.0-preview.1</version><dependencies><group targetFramework="net11.0">' +
            '<dependency id="Sample.Core" version="[1.0.0-preview.1]" /><dependency id="Other.Library" version="2.0.0" />' +
            '</group></dependencies></metadata></package>'
        $nupkg = Join-Path $directory 'Sample.Package.1.0.0-preview.1.nupkg'
        $archive = [System.IO.Compression.ZipFile]::Open($nupkg, 'Create')

        try {
            $writer = [System.IO.StreamWriter]::new($archive.CreateEntry('Sample.Package.nuspec').Open())
            $writer.Write($nuspec)
            $writer.Dispose()
        }
        finally {
            $archive.Dispose()
        }

        $tarball = [System.IO.File]::Create((Join-Path $directory 'sample-package-1.0.0-preview.1.tgz'))
        $gzip = [System.IO.Compression.GZipStream]::new($tarball, [System.IO.Compression.CompressionMode]::Compress)
        $tar = [System.Formats.Tar.TarWriter]::new($gzip)

        try {
            $entry = [System.Formats.Tar.PaxTarEntry]::new([System.Formats.Tar.TarEntryType]::RegularFile, 'package/package.json')
            $entry.DataStream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes('{ "name": "@sample/package", "version": "1.0.0-preview.1" }'))
            $tar.WriteEntry($entry)
        }
        finally {
            $tar.Dispose()
            $gzip.Dispose()
            $tarball.Dispose()
        }
        [System.IO.File]::WriteAllText((Join-Path $directory 'Sample.Package.1.0.0-preview.1.snupkg'), 'symbols')

        $packages = @(Get-PackageInventory -Directory $directory)

        if ($packages.Count -ne 2) { "$($packages.Count) packages were read" }
        $nuget = $packages | Where-Object { $_.Ecosystem -ceq 'NuGet' -and $_.Id -ceq 'Sample.Package' -and $_.Version -ceq '1.0.0-preview.1' }
        $npm = $packages | Where-Object { $_.Ecosystem -ceq 'npm' -and $_.Id -ceq '@sample/package' -and $_.Version -ceq '1.0.0-preview.1' }

        if (-not $nuget) { 'the NuGet package wasn''t read' }
        elseif (($nuget.Dependencies -join ',') -cne 'Other.Library,Sample.Core') { "the NuGet package's dependencies were read as $($nuget.Dependencies -join ',')" }
        if (-not $npm) { 'the npm package wasn''t read' }
        elseif ($npm.Dependencies.Count -ne 0) { "the npm package without dependencies was read with $($npm.Dependencies.Count)" }
    }

    'packages publish after the packages of the release they depend on, and a cycle is refused' = {
        $package = { param($Ecosystem, $Id, [string[]] $Dependencies) [pscustomobject]@{ Ecosystem = $Ecosystem; Id = $Id; Dependencies = @($Dependencies) } }
        $order = @(Get-PublicationOrder -Package @(
                (& $package NuGet 'Forma.Blazor' 'forma.framework.culture', 'Forma.Framework', 'Microsoft.JSInterop'),
                (& $package NuGet 'Forma.Framework.Culture' 'Forma.Framework'),
                (& $package NuGet 'Forma.Framework' @()),
                (& $package npm '@sample/dom' '@sample/nexo'),
                (& $package npm '@sample/nexo' @())
            ) | ForEach-Object { $_.Id })

        foreach ($pair in @('Forma.Framework', 'Forma.Framework.Culture'), @('Forma.Framework.Culture', 'Forma.Blazor'), @('@sample/nexo', '@sample/dom')) {
            if ([array]::IndexOf($order, $pair[0]) -gt [array]::IndexOf($order, $pair[1])) { "$($pair[1]) published before $($pair[0]), which it depends on: $($order -join ', ')" }
        }

        if ($order.Count -ne 5) { "$($order.Count) packages were ordered" }

        $cycle = $null

        try {
            $null = Get-PublicationOrder -Package @((& $package NuGet 'A' 'B'), (& $package NuGet 'B' 'A'))
        }
        catch {
            $cycle = $_.Exception.Message
        }

        if (-not $cycle) { 'packages depending on each other in a cycle were ordered' }
    }

    'a digests file names every package, and a changed, missing or unlisted one is found' = {
        $directory = Join-Path $scratch 'digests'
        $null = New-Item -ItemType Directory -Path $directory
        [System.IO.File]::WriteAllText((Join-Path $directory 'a.nupkg'), 'a')
        [System.IO.File]::WriteAllText((Join-Path $directory 'b.tgz'), 'b')
        New-DigestFile -Directory $directory -Path (Join-Path $directory 'SHA256SUMS')

        $whole = @(Test-DigestFile -Directory $directory)
        if ($whole.Count -gt 0) { "the packages as written failed: $($whole -join '; ')" }

        [System.IO.File]::WriteAllText((Join-Path $directory 'a.nupkg'), 'changed')
        [System.IO.File]::WriteAllText((Join-Path $directory 'c.nupkg'), 'c')
        Remove-Item -LiteralPath (Join-Path $directory 'b.tgz')
        $found = @(Test-DigestFile -Directory $directory)

        if (-not ($found -ccontains "a.nupkg doesn't match its digest")) { 'a changed package wasn''t found' }
        if (-not ($found -ccontains 'b.tgz is missing')) { 'a missing package wasn''t found' }
        if (-not ($found -ccontains "c.nupkg isn't in SHA256SUMS")) { 'an unlisted package wasn''t found' }
    }
}

try {
    foreach ($name in $cases.Keys) {
        $problems = @(& $cases[$name])
        Write-Host ('  {0} {1}' -f $(if ($problems.Count -eq 0) { 'ok  ' } else { 'FAIL' }), $name)

        foreach ($problem in $problems) {
            Write-Host "        $problem"
            "$name`: $problem"
        }
    }
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
