# The functions the promotion check, the release check and the release's packages share.

Set-StrictMode -Version Latest

$semanticVersionPattern = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)' +
    '(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?' +
    '(?:\+[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*)?$'
$months = 'January|February|March|April|May|June|July|August|September|October|November|December'

# Whether a version is one the version rules allow: X.Y.Z, X.Y.Z-preview.N or X.Y.Z-rc.N.
function Test-VersionRule {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Version)

    $Version -cmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-(preview|rc)\.[1-9]\d*)?$'
}

# A Semantic Versioning 2.0.0 version's parts, or nothing for text that isn't one.
function ConvertTo-SemanticVersion {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Version)

    $match = [regex]::Match($Version, $semanticVersionPattern)

    if ($match.Success) {
        [pscustomobject]@{
            Major      = [bigint]::Parse($match.Groups[1].Value)
            Minor      = [bigint]::Parse($match.Groups[2].Value)
            Patch      = [bigint]::Parse($match.Groups[3].Value)
            PreRelease = @(if ($match.Groups[4].Success) { $match.Groups[4].Value -split '\.' })
        }
    }
}

# Compares two versions by Semantic Versioning's precedence: below zero, zero or above zero.
function Compare-Version {
    param([Parameter(Mandatory)] [string] $Left, [Parameter(Mandatory)] [string] $Right)

    $first = ConvertTo-SemanticVersion -Version $Left
    $second = ConvertTo-SemanticVersion -Version $Right

    if (-not $first -or -not $second) {
        throw "Only Semantic Versioning versions compare: $Left, $Right."
    }

    foreach ($part in 'Major', 'Minor', 'Patch') {
        if ($first.$part -ne $second.$part) {
            return $(if ($first.$part -lt $second.$part) { -1 } else { 1 })
        }
    }

    # A version without pre-release identifiers is higher than any pre-release of it.
    if ($first.PreRelease.Count -eq 0 -or $second.PreRelease.Count -eq 0) {
        return [math]::Sign($second.PreRelease.Count - $first.PreRelease.Count)
    }

    $count = [math]::Min($first.PreRelease.Count, $second.PreRelease.Count)

    for ($index = 0; $index -lt $count; $index++) {
        $one = $first.PreRelease[$index]
        $other = $second.PreRelease[$index]
        $oneIsNumber = $one -match '^\d+$'
        $otherIsNumber = $other -match '^\d+$'

        $order = if ($oneIsNumber -and $otherIsNumber) {
            [bigint]::Parse($one).CompareTo([bigint]::Parse($other))
        }
        elseif ($oneIsNumber) {
            -1
        }
        elseif ($otherIsNumber) {
            1
        }
        else {
            [string]::CompareOrdinal($one, $other)
        }

        if ($order -ne 0) {
            return [math]::Sign($order)
        }
    }

    [math]::Sign($first.PreRelease.Count - $second.PreRelease.Count)
}

# A GitHub API response, or nothing for a resource GitHub doesn't hold where that's allowed.
function Invoke-GitHubApi {
    param([Parameter(Mandatory)] [string] $Path, [switch] $AllowNotFound)

    $output = gh api $Path 2>&1
    $text = ($output | ForEach-Object { "$_" }) -join "`n"

    if ($LASTEXITCODE -ne 0) {
        if ($AllowNotFound -and $text -match 'HTTP 404') {
            return $null
        }

        throw "gh api $Path failed: $text"
    }

    ($output | Where-Object { $_ -is [string] }) -join "`n" | ConvertFrom-Json
}

# The versions of the repository's releases: every tag that is a version, with or without a leading v.
function Get-ReleaseVersion {
    param([Parameter(Mandatory)] [string] $Repository)

    $refs = gh api "repos/$Repository/git/matching-refs/tags" --paginate --jq '.[].ref' 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Listing $Repository's tags failed: $($refs -join "`n")"
    }

    foreach ($ref in $refs) {
        $version = "$ref" -replace '^refs/tags/v?', ''

        if (ConvertTo-SemanticVersion -Version $version) {
            $version
        }
    }
}

# The highest of a set of versions by precedence, or nothing for an empty set.
function Get-HighestVersion {
    param([AllowEmptyCollection()] [string[]] $Version = @())

    $highest = $null

    foreach ($candidate in $Version) {
        if (-not $highest -or (Compare-Version -Left $candidate -Right $highest) -gt 0) {
            $highest = $candidate
        }
    }

    $highest
}

# The changelog's entry for a version: whether it has one, and whether the entry is dated.
function Get-ChangelogEntry {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [AllowEmptyString()] [string] $Version)

    $entry = [pscustomobject]@{ Found = $false; Dated = $false; Line = $null }

    if (-not (Test-Path -LiteralPath $Path)) {
        return $entry
    }

    $lines = [System.IO.File]::ReadAllLines($Path)
    $heading = "## ``$Version``"

    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].TrimEnd() -cne $heading) {
            continue
        }

        $entry.Found = $true
        $next = $lines | Select-Object -Skip ($index + 1) | Where-Object { $_.Trim() } | Select-Object -First 1
        $entry.Line = $next
        $entry.Dated = [bool]($next -and $next -cmatch "^\*($months) [1-9]\d?, \d{4}(\*| ·)")
        break
    }

    $entry
}

# The latest run of the full-gate workflow that passed on a push to candidate for a commit, or nothing.
function Find-GateRun {
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string] $Workflow,
        [Parameter(Mandatory)] [string] $Commit
    )

    $runs = Invoke-GitHubApi -Path "repos/$Repository/actions/workflows/$Workflow/runs?branch=candidate&event=push&status=success&head_sha=$Commit&per_page=100"
    $runs.workflow_runs | Where-Object { $_.head_sha -ceq $Commit } | Sort-Object -Property id -Descending | Select-Object -First 1
}

# A run's artifact of a name, while the run still holds it.
function Get-RunArtifact {
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $Name
    )

    $list = Invoke-GitHubApi -Path "repos/$Repository/actions/runs/$RunId/artifacts?name=$([uri]::EscapeDataString($Name))&per_page=100"
    $list.artifacts | Where-Object { $_.name -ceq $Name -and -not $_.expired } | Select-Object -First 1
}

# Saves a run's artifact into a directory.
function Save-RunArtifact {
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Directory
    )

    $output = gh run download $RunId --repo $Repository --name $Name --dir $Directory 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Downloading the artifact $Name of run $RunId failed: $($output -join "`n")"
    }
}

# The packages in a directory, each with its ecosystem, id, version and the ids it depends on, read from the package
# itself.
function Get-PackageInventory {
    param([Parameter(Mandatory)] [string] $Directory)

    foreach ($file in Get-ChildItem -LiteralPath $Directory -File -Recurse | Sort-Object -Property Name) {
        if ($file.Name -like '*.nupkg') {
            $archive = [System.IO.Compression.ZipFile]::OpenRead($file.FullName)

            try {
                $entry = $archive.Entries | Where-Object { $_.FullName -notmatch '/' -and $_.Name -like '*.nuspec' } | Select-Object -First 1
                $reader = [System.IO.StreamReader]::new($entry.Open())

                try {
                    $nuspec = [xml]$reader.ReadToEnd()
                }
                finally {
                    $reader.Dispose()
                }

                $metadata = $nuspec.package.metadata
                $dependencies = @($nuspec.SelectNodes("//*[local-name()='dependency']") | ForEach-Object { $_.GetAttribute('id') } | Sort-Object -Unique)
                [pscustomobject]@{ Ecosystem = 'NuGet'; Id = $metadata.id; Version = $metadata.version; Dependencies = $dependencies; Path = $file.FullName }
            }
            finally {
                $archive.Dispose()
            }
        }
        elseif ($file.Name -like '*.tgz') {
            $stream = [System.IO.File]::OpenRead($file.FullName)
            $gzip = [System.IO.Compression.GZipStream]::new($stream, [System.IO.Compression.CompressionMode]::Decompress)
            $tar = [System.Formats.Tar.TarReader]::new($gzip)
            $manifest = $null

            try {
                while ($entry = $tar.GetNextEntry()) {
                    if ($entry.Name -ceq 'package/package.json' -and $entry.DataStream) {
                        $manifest = [System.IO.StreamReader]::new($entry.DataStream).ReadToEnd() | ConvertFrom-Json
                        break
                    }
                }
            }
            finally {
                $tar.Dispose()
                $gzip.Dispose()
                $stream.Dispose()
            }

            if (-not $manifest) {
                throw "$($file.Name) doesn't hold package/package.json, so it isn't an npm package."
            }

            $dependencies = @(@(foreach ($field in 'dependencies', 'peerDependencies', 'optionalDependencies') {
                        if ($manifest.PSObject.Properties[$field]) {
                            $manifest.$field.PSObject.Properties.Name
                        }
                    }) | Sort-Object -Unique)
            [pscustomobject]@{ Ecosystem = 'npm'; Id = $manifest.name; Version = $manifest.version; Dependencies = $dependencies; Path = $file.FullName }
        }
    }
}

# A release's packages in the order they publish, each after the packages of the release it depends on.
function Get-PublicationOrder {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Package)

    $remaining = [System.Collections.Generic.List[object]]::new()

    foreach ($item in $Package | Sort-Object -Property Ecosystem, Id) {
        $remaining.Add($item)
    }

    while ($remaining.Count -gt 0) {
        $ready = @(foreach ($item in $remaining) {
                $waiting = $false

                foreach ($dependency in $item.Dependencies) {
                    foreach ($other in $remaining) {
                        if ($other.Ecosystem -ceq $item.Ecosystem -and $other.Id -ieq $dependency) {
                            $waiting = $true
                        }
                    }
                }

                if (-not $waiting) {
                    $item
                }
            })

        if ($ready.Count -eq 0) {
            throw "The packages depend on each other in a cycle: $(($remaining | ForEach-Object { $_.Id }) -join ', ')."
        }

        foreach ($item in $ready) {
            $item
            $null = $remaining.Remove($item)
        }
    }
}

# Whether an ecosystem's public registry holds a version of a package.
function Test-FeedVersion {
    param(
        [Parameter(Mandatory)] [ValidateSet('NuGet', 'npm')] [string] $Ecosystem,
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $Version
    )

    $uri = if ($Ecosystem -eq 'NuGet') {
        "https://api.nuget.org/v3-flatcontainer/$($Id.ToLowerInvariant())/index.json"
    }
    else {
        "https://registry.npmjs.org/$($Id -replace '/', '%2F')"
    }

    try {
        $document = Invoke-RestMethod -Uri $uri -Headers @{ Accept = 'application/vnd.npm.install-v1+json, application/json' }
    }
    catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
            return $false
        }

        throw
    }

    if ($Ecosystem -eq 'NuGet') {
        @($document.versions) -contains $Version.ToLowerInvariant()
    }
    else {
        @($document.versions.PSObject.Properties.Name) -ccontains $Version
    }
}

# Writes a digests file naming each file in a directory with its SHA-256, as sha256sum writes one.
function New-DigestFile {
    param([Parameter(Mandatory)] [string] $Directory, [Parameter(Mandatory)] [string] $Path)

    $files = @(Get-ChildItem -LiteralPath $Directory -File -Recurse | Where-Object { $_.FullName -ne $Path } | Sort-Object -Property Name)
    $duplicate = $files | Group-Object -Property Name | Where-Object { $_.Count -gt 1 } | Select-Object -First 1

    if ($duplicate) {
        throw "Two packages share the file name $($duplicate.Name), which a release's assets can't hold."
    }

    $lines = foreach ($file in $files) {
        '{0}  {1}' -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $file.Name
    }

    [System.IO.File]::WriteAllText($Path, (($lines -join "`n") + "`n"))
}

# The problems with a directory's files against the digests file in it: a file it lists that's missing or differs,
# and a file it doesn't list.
function Test-DigestFile {
    param([Parameter(Mandatory)] [string] $Directory, [string] $Name = 'SHA256SUMS')

    $path = Join-Path $Directory $Name

    if (-not (Test-Path -LiteralPath $path)) {
        return "$Name is missing"
    }

    $listed = @{}

    foreach ($line in [System.IO.File]::ReadAllLines($path) | Where-Object { $_ }) {
        $match = [regex]::Match($line, '^([0-9a-f]{64})  (.+)$')

        if (-not $match.Success) {
            "$Name has a line that isn't a digest and a file name: $line"
            continue
        }

        $listed[$match.Groups[2].Value] = $match.Groups[1].Value
    }

    foreach ($file in $listed.Keys | Sort-Object) {
        $filePath = Join-Path $Directory $file

        if (-not (Test-Path -LiteralPath $filePath)) {
            "$file is missing"
        }
        elseif ((Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $listed[$file]) {
            "$file doesn't match its digest"
        }
    }

    foreach ($file in Get-ChildItem -LiteralPath $Directory -File | Where-Object { $_.Name -cne $Name }) {
        if (-not $listed.ContainsKey($file.Name)) {
            "$($file.Name) isn't in $Name"
        }
    }
}

# One check's result: whether it holds, and what it found.
function New-CheckResult {
    param([Parameter(Mandatory)] [string] $Check, [Parameter(Mandatory)] [bool] $Holds, [Parameter(Mandatory)] [string] $Detail)

    [pscustomobject]@{ Check = $Check; Holds = $Holds; Detail = $Detail }
}

# Writes a check's results to the log and the job's summary, and returns how many failed.
function Write-CheckResult {
    param([Parameter(Mandatory)] [string] $Title, [Parameter(Mandatory)] [object[]] $Result)

    Write-Host $Title

    foreach ($item in $Result) {
        Write-Host ('  {0}  {1,-10} {2}' -f $(if ($item.Holds) { 'holds' } else { 'FAILS' }), $item.Check, $item.Detail)
    }

    if ($env:GITHUB_STEP_SUMMARY) {
        $rows = foreach ($item in $Result) {
            '| {0} | {1} | {2} |' -f $item.Check, $(if ($item.Holds) { 'Holds' } else { '**Fails**' }), ($item.Detail -replace '\|', '\|')
        }

        $summary = @("### $Title", '', '| Check | Result | What it found |', '| --- | --- | --- |') + $rows + ''
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary
    }

    @($Result | Where-Object { -not $_.Holds }).Count
}

Export-ModuleMember -Function Test-VersionRule, Compare-Version, Invoke-GitHubApi, Get-ReleaseVersion, Get-HighestVersion,
    Get-ChangelogEntry, Find-GateRun, Get-RunArtifact, Save-RunArtifact, Get-PackageInventory, Get-PublicationOrder,
    Test-FeedVersion, New-DigestFile, Test-DigestFile, New-CheckResult, Write-CheckResult
