#Requires -Version 5.1
<#
.SYNOPSIS
    Installs CursorSkills into the user's personal Cursor skills directory.

.DESCRIPTION
    Installs skills from skills/ to %USERPROFILE%\.cursor\skills\<skill-name>.
    Compares version in SKILL.md frontmatter:
    - Installs when skill is missing
    - Reinstalls when source version is higher than installed
    - Reinstalls when installed copy has no version field
    - Skips when installed version is greater or equal to source

    Default mode creates junction links (live sync with repo).
    Use -Copy for a full directory copy instead of junctions.

.PARAMETER Copy
    Copy files instead of creating junctions (use when symlinks are not allowed).

.EXAMPLE
    .\scripts\install.ps1
    .\scripts\install.ps1 -Copy
#>
param(
    [switch]$Copy
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SkillsSource = Join-Path $RepoRoot "skills"
$SkillsTarget = Join-Path $env:USERPROFILE ".cursor\skills"

function Get-SkillVersion {
    param([string]$SkillMdPath)

    if (-not (Test-Path $SkillMdPath)) {
        return $null
    }

    $content = Get-Content $SkillMdPath -Raw
    if ($content -match '(?m)^version:\s*([0-9]+(?:\.[0-9]+)*)\s*$') {
        return [version]$Matches[1]
    }

    return $null
}

function Format-SkillVersion {
    param([version]$Version)

    if ($null -eq $Version) {
        return "none"
    }

    return $Version.ToString()
}

function Remove-SkillInstallation {
    param([string]$TargetPath)

    if (-not (Test-Path $TargetPath)) {
        return
    }

    Remove-Item $TargetPath -Force -Recurse
    Write-Host "Removed existing installation: $TargetPath"
}

function Test-ShouldReinstallSkill {
    param(
        [version]$SourceVersion,
        [version]$InstalledVersion
    )

    if ($null -eq $SourceVersion) {
        throw "Source SKILL.md must contain a version field (e.g. version: 1.0.0)."
    }

    if ($null -eq $InstalledVersion) {
        return $true
    }

    return $SourceVersion -gt $InstalledVersion
}

if (-not (Test-Path $SkillsSource)) {
    Write-Error "Skills directory not found: $SkillsSource"
}

if (-not (Test-Path $SkillsTarget)) {
    New-Item -ItemType Directory -Path $SkillsTarget -Force | Out-Null
    Write-Host "Created: $SkillsTarget"
}

$skillDirs = Get-ChildItem -Path $SkillsSource -Directory

if ($skillDirs.Count -eq 0) {
    Write-Warning "No skills found in $SkillsSource"
    exit 0
}

$installed = @()
$skipped = @()

foreach ($skill in $skillDirs) {
    $targetPath = Join-Path $SkillsTarget $skill.Name
    $sourcePath = $skill.FullName
    $sourceSkillMd = Join-Path $sourcePath "SKILL.md"
    $targetSkillMd = Join-Path $targetPath "SKILL.md"

    $sourceVersion = Get-SkillVersion -SkillMdPath $sourceSkillMd
    $installedVersion = Get-SkillVersion -SkillMdPath $targetSkillMd

    if (-not (Test-ShouldReinstallSkill -SourceVersion $sourceVersion -InstalledVersion $installedVersion)) {
        $skipped += [PSCustomObject]@{
            Name    = $skill.Name
            Source  = Format-SkillVersion $sourceVersion
            Current = Format-SkillVersion $installedVersion
        }
        Write-Host "Skipping '$($skill.Name)' - installed $(Format-SkillVersion $installedVersion) >= source $(Format-SkillVersion $sourceVersion)"
        continue
    }

    if (Test-Path $targetPath) {
        if ($null -eq $installedVersion) {
            Write-Host "Upgrading '$($skill.Name)' - installed version missing, source $(Format-SkillVersion $sourceVersion)"
        }
        else {
            Write-Host "Upgrading '$($skill.Name)' - $(Format-SkillVersion $installedVersion) -> $(Format-SkillVersion $sourceVersion)"
        }

        Remove-SkillInstallation -TargetPath $targetPath
    }
    else {
        Write-Host "Installing '$($skill.Name)' v$(Format-SkillVersion $sourceVersion)"
    }

    if ($Copy) {
        Copy-Item -Path $sourcePath -Destination $targetPath -Recurse -Force
        Write-Host "Copied: $($skill.Name) v$(Format-SkillVersion $sourceVersion) -> $targetPath"
    }
    else {
        New-Item -ItemType Junction -Path $targetPath -Target $sourcePath -Force | Out-Null
        Write-Host "Linked: $($skill.Name) v$(Format-SkillVersion $sourceVersion) -> $targetPath"
    }

    $installed += [PSCustomObject]@{
        Name    = $skill.Name
        Version = Format-SkillVersion $sourceVersion
    }
}

Write-Host ""

if ($installed.Count -gt 0) {
    Write-Host "Installed skills:"
    foreach ($item in $installed) {
        Write-Host "  - $($item.Name) v$($item.Version)"
    }
}

if ($skipped.Count -gt 0) {
    Write-Host ""
    Write-Host "Skipped (already up to date):"
    foreach ($item in $skipped) {
        Write-Host "  - $($item.Name) (installed v$($item.Current), source v$($item.Source))"
    }
}

Write-Host ""
Write-Host "Restart Cursor to load updated skills."
Write-Host 'Use /dotnet-clean-architecture or /dotnet-tester in Agent chat to invoke skills.'
