#Requires -Version 5.1
<#
.SYNOPSIS
    Validates all CursorSkills in skills/*/.

.EXAMPLE
    .\scripts\validate.ps1
#>
param()

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SkillsRoot = Join-Path $RepoRoot "skills"

$errors = @()
$warnings = @()

function Add-Error([string]$Message) {
    $script:errors += $Message
}

function Add-Warning([string]$Message) {
    $script:warnings += $Message
}

function Validate-Skill {
    param(
        [string]$SkillRoot,
        [string]$SkillName
    )

    $SkillMd = Join-Path $SkillRoot "SKILL.md"
    $relativeSkillRoot = $SkillRoot.Substring($RepoRoot.Length + 1)

    Write-Host ""
    Write-Host "=== Validating $SkillName ==="

    if (-not (Test-Path $SkillMd)) {
        Add-Error "$relativeSkillRoot`: SKILL.md not found"
        return
    }

    # 1. SKILL.md line count
    $skillLines = (Get-Content $SkillMd | Measure-Object -Line).Lines
    if ($skillLines -gt 500) {
        Add-Error "$relativeSkillRoot/SKILL.md has $skillLines lines (max 500). Move detail to reference/."
    }
    else {
        Write-Host "OK: SKILL.md has $skillLines lines (max 500)"
    }

    # 2. Frontmatter checks
    $skillContent = Get-Content $SkillMd -Raw

    if ($skillContent -notmatch '(?m)^name:\s*\S') {
        Add-Error "$relativeSkillRoot/SKILL.md`: missing 'name' in frontmatter"
    }

    if ($skillContent -notmatch '(?m)^description:\s*') {
        Add-Error "$relativeSkillRoot/SKILL.md`: missing 'description' in frontmatter"
    }

    if ($skillContent -match '(?m)^version:\s*([0-9]+(?:\.[0-9]+)*)\s*$') {
        Write-Host "OK: version $($Matches[1])"
    }
    else {
        Add-Error "$relativeSkillRoot/SKILL.md`: missing 'version' in frontmatter (e.g. version: 1.0.0)"
    }

    if ($skillContent -notmatch '(?m)^disable-model-invocation:\s*true\s*$') {
        Add-Error "$relativeSkillRoot/SKILL.md`: must keep disable-model-invocation: true (manual invocation only)."
    }
    else {
        Write-Host "OK: disable-model-invocation: true"
    }

    # Skill-specific checks
    if ($SkillName -eq "dotnet-clean-architecture") {
        if ($skillContent -match 'behavior-rich') {
            Add-Error "$relativeSkillRoot/SKILL.md`: description contains typo 'behavior-rich'."
        }
        else {
            Write-Host "OK: description typo check passed"
        }

        $forbiddenPattern = '(?i)(Application/|Orders/)Commands/'
        $markdownFiles = Get-ChildItem -Path $SkillRoot -Recurse -Filter "*.md" -File

        foreach ($file in $markdownFiles) {
            $relativePath = $file.FullName.Substring($RepoRoot.Length + 1)
            $lines = Get-Content $file.FullName

            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match $forbiddenPattern) {
                    Add-Error "$relativePath`:$($i + 1) uses Commands/ subfolder. Use flat use-case folders."
                }
            }
        }

        if ($errors.Count -eq 0) {
            Write-Host "OK: no Commands/ subfolder paths in examples"
        }

        $requiredRefs = @(
            "reference/team-conventions.md",
            "reference/project-layout.md",
            "reference/mediatr-setup.md",
            "reference/domain-entities.md",
            "reference/dapper-persistence.md",
            "reference/controllers.md",
            "reference/error-handling.md",
            "reference/logging.md",
            "reference/program-and-di.md",
            "reference/migrations.md",
            "reference/docker.md",
            "reference/architecture-tests.md",
            "reference/result-pattern.md",
            "examples.md"
        )

        foreach ($ref in $requiredRefs) {
            $fullPath = Join-Path $SkillRoot $ref
            if (-not (Test-Path $fullPath)) {
                Add-Error "Missing required file: $relativeSkillRoot/$ref"
            }
        }

        if ($errors.Count -eq 0) {
            Write-Host "OK: all required reference files exist"
        }
    }

    if ($SkillName -eq "dotnet-tester") {
        $requiredRefs = @(
            "reference/webapi-discovery.md",
            "reference/build-and-unit-tests.md",
            "reference/docker-compose.md",
            "reference/curl-prerequisites.md",
            "reference/openapi-discovery.md",
            "reference/ai-e2e-tests-format.md",
            "reference/report-format.md",
            "examples.md"
        )

        foreach ($ref in $requiredRefs) {
            $fullPath = Join-Path $SkillRoot $ref
            if (-not (Test-Path $fullPath)) {
                Add-Error "Missing required file: $relativeSkillRoot/$ref"
            }
        }

        if ($errors.Count -eq 0) {
            Write-Host "OK: all required reference files exist"
        }
    }

    # Markdown link targets (relative links only)
    $markdownFiles = Get-ChildItem -Path $SkillRoot -Recurse -Filter "*.md" -File
    $linkPattern = '\[[^\]]+\]\(([^)]+)\)'
    $linkErrorsBefore = $errors.Count

    foreach ($file in $markdownFiles) {
        $relativePath = $file.FullName.Substring($RepoRoot.Length + 1)
        $content = Get-Content $file.FullName -Raw
        $matches = [regex]::Matches($content, $linkPattern)

        foreach ($match in $matches) {
            $target = $match.Groups[1].Value.Trim()

            if ($target -match '^(https?://|mailto:|#)') {
                continue
            }

            $targetPath = $target -replace '#.*$', ''
            if ([string]::IsNullOrWhiteSpace($targetPath)) {
                continue
            }

            $resolved = Join-Path $file.DirectoryName $targetPath
            $resolved = [System.IO.Path]::GetFullPath($resolved)

            if (-not (Test-Path $resolved)) {
                Add-Error "$relativePath`: broken link '$target' -> '$resolved'"
            }
        }
    }

    if ($errors.Count -eq $linkErrorsBefore) {
        Write-Host "OK: all relative markdown links resolve"
    }
}

if (-not (Test-Path $SkillsRoot)) {
    Write-Error "Skills directory not found: $SkillsRoot"
}

$skillDirs = Get-ChildItem -Path $SkillsRoot -Directory

if ($skillDirs.Count -eq 0) {
    Write-Warning "No skills found in $SkillsRoot"
    exit 0
}

foreach ($skill in $skillDirs) {
    Validate-Skill -SkillRoot $skill.FullName -SkillName $skill.Name
}

Write-Host ""

if ($warnings.Count -gt 0) {
    Write-Host "Warnings:"
    foreach ($warning in $warnings) {
        Write-Host "  WARN: $warning"
    }
    Write-Host ""
}

if ($errors.Count -gt 0) {
    Write-Host "Validation failed ($($errors.Count) error(s)):"
    foreach ($err in $errors) {
        Write-Host "  ERROR: $err"
    }
    exit 1
}

Write-Host "Validation passed ($($skillDirs.Count) skill(s))."
