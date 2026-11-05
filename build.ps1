#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
Runs Versioning's gate.

.DESCRIPTION
Checks that every link and anchor the repository's documents give resolves, that VERSION declares a version by the
version rules, the one the changelog's newest entry names, and runs the cases of the functions the checks share. Every
problem is listed, and any problem fails the gate.

.EXAMPLE
./build.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$problems = [System.Collections.Generic.List[string]]::new()
$anchorCache = @{}

# The lines of a document outside its fenced code blocks, which hold neither headings nor links.
function Get-ProseLine {
    param([string] $Path)

    $fenced = $false

    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*(```|~~~)') {
            $fenced = -not $fenced
        }
        elseif (-not $fenced) {
            $line
        }
    }
}

# The anchors GitHub gives a document: each heading's slug, numbered from the second time it repeats, and each
# explicit id.
function Get-Anchor {
    param([string] $Path)

    if (-not $anchorCache.ContainsKey($Path)) {
        $anchors = [System.Collections.Generic.HashSet[string]]::new()
        $repeats = @{}

        foreach ($line in Get-ProseLine -Path $Path) {
            if ($line -match '^#{1,6}\s+(.+?)\s*#*\s*$') {
                $text = $Matches[1] -replace '\[([^\]]*)\]\([^)]*\)', '$1'
                $slug = ($text.ToLowerInvariant() -replace '[^\p{L}\p{Mn}\p{Nd}\p{Pc} -]', '') -replace ' ', '-'
                $count = if ($repeats.ContainsKey($slug)) { $repeats[$slug] } else { 0 }
                $repeats[$slug] = $count + 1
                $null = $anchors.Add($(if ($count -eq 0) { $slug } else { "$slug-$count" }))
            }

            foreach ($match in [regex]::Matches($line, '<a\s+(?:id|name)="([^"]+)"')) {
                $null = $anchors.Add($match.Groups[1].Value)
            }
        }

        $anchorCache[$Path] = $anchors
    }

    $anchorCache[$Path]
}

$documents = @(Get-ChildItem -LiteralPath $root -Filter '*.md' -File -Recurse |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        Sort-Object FullName)
$linkCount = 0

foreach ($document in $documents) {
    $name = [System.IO.Path]::GetRelativePath($root, $document.FullName).Replace('\', '/')

    foreach ($line in Get-ProseLine -Path $document.FullName) {
        # A link written inside inline code is text, as the example address in the README is.
        $prose = $line -replace '`[^`]*`', ''

        foreach ($match in [regex]::Matches($prose, '\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)')) {
            $target = $match.Groups[1].Value
            $linkCount++

            if ($target -match '^(https?|mailto):') {
                continue
            }

            $path, $fragment = $target -split '#', 2
            $resolved = if ($path) {
                [System.IO.Path]::GetFullPath((Join-Path $document.DirectoryName ([uri]::UnescapeDataString($path))))
            }
            else {
                $document.FullName
            }

            if (-not (Test-Path -LiteralPath $resolved)) {
                $problems.Add("$name links to $target, and $path doesn't exist")
            }
            elseif ($fragment -and $resolved.EndsWith('.md') -and -not (Get-Anchor -Path $resolved).Contains($fragment)) {
                $problems.Add("$name links to $target, and its document doesn't have a heading or id #$fragment")
            }
        }
    }
}

$versionPath = Join-Path $root 'VERSION'
$changelogPath = Join-Path $root 'CHANGELOG.md'
$version = if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw).Trim() } else { $null }

if (-not $version) {
    $problems.Add('VERSION is missing or empty')
}
elseif ($version -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-(preview|rc)\.[1-9]\d*)?$') {
    $problems.Add("VERSION declares $version, which isn't a version by the version rules")
}

$newest = if (Test-Path -LiteralPath $changelogPath) {
    Get-ProseLine -Path $changelogPath | Where-Object { $_ -match '^## ' } | Select-Object -First 1
}

if (-not $newest) {
    $problems.Add('The changelog doesn''t have an entry')
}
elseif ($version -and $newest -notmatch "^## ``$([regex]::Escape($version))``\s*$") {
    $problems.Add("The changelog's newest entry is $($newest.Substring(3)), and VERSION declares $version")
}

Write-Host "Checked $($documents.Count) documents and the $linkCount links they give, and VERSION, $version."
Write-Host 'The cases of the functions the checks share:'

foreach ($problem in @(& (Join-Path $root 'tests' 'Versioning.Tests.ps1'))) {
    $problems.Add($problem)
}

if ($problems.Count -gt 0) {
    foreach ($problem in $problems) {
        Write-Host "  $problem"
    }

    Write-Host "The gate failed: $($problems.Count) $(if ($problems.Count -eq 1) { 'problem' } else { 'problems' })."
    exit 1
}

Write-Host 'The gate passed.'
