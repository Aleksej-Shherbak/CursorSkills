#Requires -Version 5.1
<#
.SYNOPSIS
    Validates CursorSkills structure and dotnet-clean-architecture conventions.

.EXAMPLE
    .\scripts\validate.ps1
#>
param()

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SkillRoot = Join-Path $RepoRoot "skills\dotnet-clean-architecture"
$SkillMd = Join-Path $SkillRoot "SKILL.md"

$errors = @()
$warnings = @()

function Add-Error([string]$Message) {
    $script:errors += $Message
}

function Add-Warning([string]$Message) {
    $script:warnings += $Message
}

if (-not (Test-Path $SkillMd)) {
    Write-Error "SKILL.md not found: $SkillMd"
}

# 1. SKILL.md line count
$skillLines = (Get-Content $SkillMd | Measure-Object -Line).Lines
if ($skillLines -gt 500) {
    Add-Error "SKILL.md has $skillLines lines (max 500). Move detail to reference/."
}
else {
    Write-Host "OK: SKILL.md has $skillLines lines (max 500)"
}

# 2. Frontmatter checks
$skillContent = Get-Content $SkillMd -Raw
if ($skillContent -notmatch '(?m)^disable-model-invocation:\s*true\s*$') {
    Add-Error "SKILL.md must keep disable-model-invocation: true (manual invocation only)."
}
else {
    Write-Host "OK: disable-model-invocation: true"
}

if ($skillContent -match 'behavior-rich') {
    Add-Error "SKILL.md description contains typo 'behavior-rich'. Use 'pipeline behaviors, rich domain entities'."
}
else {
    Write-Host "OK: description typo check passed"
}

# 3. Forbidden use-case path pattern (Commands/ subfolder)
$markdownFiles = Get-ChildItem -Path $SkillRoot -Recurse -Filter "*.md" -File
$forbiddenPattern = '(?i)(Application/|Orders/)Commands/'

foreach ($file in $markdownFiles) {
    $relativePath = $file.FullName.Substring($RepoRoot.Length + 1)
    $lines = Get-Content $file.FullName

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match $forbiddenPattern) {
            Add-Error "$relativePath`:$($i + 1) uses Commands/ subfolder. Use flat use-case folders (e.g. Orders/CreateOrder/)."
        }
    }
}

if ($errors.Count -eq 0) {
    Write-Host "OK: no Commands/ subfolder paths in examples"
}

# 4. Markdown link targets (relative links only)
$linkPattern = '\[[^\]]+\]\(([^)]+)\)'

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

if ($errors.Count -eq 0) {
    Write-Host "OK: all relative markdown links resolve"
}

# 5. Required reference files linked from SKILL.md
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
        Add-Error "Missing required file: skills/dotnet-clean-architecture/$ref"
    }
}

if ($errors.Count -eq 0) {
    Write-Host "OK: all required reference files exist"
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
    Write-Host "Validation failed:"
    foreach ($error in $errors) {
        Write-Host "  ERROR: $error"
    }
    exit 1
}

Write-Host "Validation passed."
