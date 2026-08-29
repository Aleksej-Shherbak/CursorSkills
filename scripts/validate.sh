#!/usr/bin/env bash
# Validates all CursorSkills in skills/*/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_ROOT="$REPO_ROOT/skills"

errors=()
warnings=()

add_error() {
    errors+=("$1")
}

add_warning() {
    warnings+=("$1")
}

validate_skill() {
    local skill_root="$1"
    local skill_name="$2"
    local skill_md="$skill_root/SKILL.md"
    local rel_root="${skill_root#"$REPO_ROOT"/}"

    echo ""
    echo "=== Validating $skill_name ==="

    if [[ ! -f "$skill_md" ]]; then
        add_error "$rel_root: SKILL.md not found"
        return
    fi

    # 1. SKILL.md line count
    local skill_lines
    skill_lines="$(wc -l < "$skill_md" | tr -d ' ')"
    if (( skill_lines > 500 )); then
        add_error "$rel_root/SKILL.md has $skill_lines lines (max 500). Move detail to reference/."
    else
        echo "OK: SKILL.md has $skill_lines lines (max 500)"
    fi

    # 2. Frontmatter checks
    if ! grep -qE '^name:[[:space:]]*[^[:space:]]' "$skill_md"; then
        add_error "$rel_root/SKILL.md: missing 'name' in frontmatter"
    fi

    if ! grep -qE '^description:[[:space:]]*' "$skill_md"; then
        add_error "$rel_root/SKILL.md: missing 'description' in frontmatter"
    fi

    if grep -qE '^version:[[:space:]]*[0-9]+(\.[0-9]+)*[[:space:]]*$' "$skill_md"; then
        local version
        version="$(grep -E '^version:[[:space:]]*[0-9]+(\.[0-9]+)*[[:space:]]*$' "$skill_md" | head -n 1 | sed -E 's/^version:[[:space:]]*//')"
        echo "OK: version $version"
    else
        add_error "$rel_root/SKILL.md: missing 'version' in frontmatter (e.g. version: 1.0.0)"
    fi

    if ! grep -qE '^disable-model-invocation:[[:space:]]*true[[:space:]]*$' "$skill_md"; then
        add_error "$rel_root/SKILL.md: must keep disable-model-invocation: true (manual invocation only)."
    else
        echo "OK: disable-model-invocation: true"
    fi

    # Skill-specific checks
    if [[ "$skill_name" == "dotnet-clean-architecture" ]]; then
        if grep -q 'behavior-rich' "$skill_md"; then
            add_error "$rel_root/SKILL.md: description contains typo 'behavior-rich'."
        else
            echo "OK: description typo check passed"
        fi

        local errors_before=${#errors[@]}
        while IFS= read -r -d '' file; do
            local rel="${file#"$REPO_ROOT"/}"
            local line_no=0
            while IFS= read -r line || [[ -n "$line" ]]; do
                ((line_no++)) || true
                if [[ "$line" =~ (Application/|Orders/)Commands/ ]]; then
                    add_error "$rel:$line_no uses Commands/ subfolder. Use flat use-case folders."
                fi
            done < "$file"
        done < <(find "$skill_root" -type f -name '*.md' -print0)

        if [[ ${#errors[@]} -eq $errors_before ]]; then
            echo "OK: no Commands/ subfolder paths in examples"
        fi

        local required_refs=(
            reference/team-conventions.md
            reference/project-layout.md
            reference/mediatr-setup.md
            reference/domain-entities.md
            reference/dapper-persistence.md
            reference/controllers.md
            reference/error-handling.md
            reference/logging.md
            reference/program-and-di.md
            reference/migrations.md
            reference/docker.md
            reference/architecture-tests.md
            reference/result-pattern.md
            examples.md
        )

        for ref in "${required_refs[@]}"; do
            if [[ ! -f "$skill_root/$ref" ]]; then
                add_error "Missing required file: $rel_root/$ref"
            fi
        done

        if [[ ${#errors[@]} -eq $errors_before ]]; then
            echo "OK: all required reference files exist"
        fi
    fi

    if [[ "$skill_name" == "dotnet-tester" ]]; then
        local errors_before=${#errors[@]}
        local required_refs=(
            reference/webapi-discovery.md
            reference/build-and-unit-tests.md
            reference/docker-compose.md
            reference/curl-prerequisites.md
            reference/openapi-discovery.md
            reference/ai-e2e-tests-format.md
            reference/report-format.md
            examples.md
        )

        for ref in "${required_refs[@]}"; do
            if [[ ! -f "$skill_root/$ref" ]]; then
                add_error "Missing required file: $rel_root/$ref"
            fi
        done

        if [[ ${#errors[@]} -eq $errors_before ]]; then
            echo "OK: all required reference files exist"
        fi
    fi
}

if [[ ! -d "$SKILLS_ROOT" ]]; then
    echo "Error: skills directory not found: $SKILLS_ROOT" >&2
    exit 1
fi

shopt -s nullglob
skill_dirs=("$SKILLS_ROOT"/*/)

if [[ ${#skill_dirs[@]} -eq 0 ]]; then
    echo "Warning: no skills found in $SKILLS_ROOT"
    exit 0
fi

for skill_path in "${skill_dirs[@]}"; do
    skill_name="$(basename "$skill_path")"
    validate_skill "$skill_path" "$skill_name"
done

echo ""

if [[ ${#warnings[@]} -gt 0 ]]; then
    echo "Warnings:"
    for warning in "${warnings[@]}"; do
        echo "  WARN: $warning"
    done
    echo ""
fi

if [[ ${#errors[@]} -gt 0 ]]; then
    echo "Validation failed (${#errors[@]} error(s)):"
    for err in "${errors[@]}"; do
        echo "  ERROR: $err"
    done
    exit 1
fi

echo "Validation passed (${#skill_dirs[@]} skill(s))."
