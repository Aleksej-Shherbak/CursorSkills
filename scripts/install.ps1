#Requires -Version 5.1
<#
.SYNOPSIS
    Installs CursorSkills into the user's personal Cursor skills directory.

.DESCRIPTION
    Creates junction links from each skill in skills/ to %USERPROFILE%\.cursor\skills\<skill-name>.
    Junctions keep skills in sync with this repository without copying files.

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

foreach ($skill in $skillDirs) {
    $targetPath = Join-Path $SkillsTarget $skill.Name
    $sourcePath = $skill.FullName

    if (Test-Path $targetPath) {
        $existing = Get-Item $targetPath -Force

        if ($existing.LinkType -eq "Junction" -or $existing.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Remove-Item $targetPath -Force -Recurse
            Write-Host "Removed existing junction: $targetPath"
        }
        elseif ($Copy) {
            Remove-Item $targetPath -Force -Recurse
            Write-Host "Removed existing directory: $targetPath"
        }
        else {
            Write-Warning "Skipping '$($skill.Name)' - path already exists: $targetPath (use -Copy to replace)"
            continue
        }
    }

    if ($Copy) {
        Copy-Item -Path $sourcePath -Destination $targetPath -Recurse -Force
        Write-Host "Copied: $($skill.Name) -> $targetPath"
    }
    else {
        New-Item -ItemType Junction -Path $targetPath -Target $sourcePath -Force | Out-Null
        Write-Host "Linked: $($skill.Name) -> $targetPath"
    }

    $installed += $skill.Name
}

Write-Host ""
Write-Host "Installed skills:"
foreach ($name in $installed) {
    Write-Host "  - $name"
}

Write-Host ""
Write-Host "Restart Cursor to load the new skills."
Write-Host 'Use @dotnet-clean-architecture in Agent chat to invoke the skill.'
