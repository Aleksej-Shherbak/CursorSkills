#!/usr/bin/env bash
# Validates CursorSkills structure and dotnet-clean-architecture conventions.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_ROOT="$REPO_ROOT/skills/dotnet-clean-architecture"
SKILL_MD="$SKILL_ROOT/SKILL.md"

errors=()
warnings=()

add_error() {
    errors+=("$1")
}

add_warning() {
    warnings+=("$1")
}

if [[ ! -f "$SKILL_MD" ]]; then
    echo "Error: SKILL.md not found: $SKILL_MD" >&2
    exit 1
fi

# 1. SKILL.md line count
skill_lines="$(wc -l < "$SKILL_MD" | tr -d ' ')"
if (( skill_lines > 500 )); then
    add_error "SKILL.md has $skill_lines lines (max 500). Move detail to reference/."
else
    echo "OK: SKILL.md has $skill_lines lines (max 500)"
fi

# 2. Frontmatter checks
if ! grep -qE '^disable-model-invocation:[[:space:]]*true[[:space:]]*$' "$SKILL_MD"; then
    add_error "SKILL.md must keep disable-model-invocation: true (manual invocation only)."
else
    echo "OK: disable-model-invocation: true"
fi

if grep -q 'behavior-rich' "$SKILL_MD"; then
    add_error "SKILL.md description contains typo 'behavior-rich'. Use 'pipeline behaviors, rich domain entities'."
else
    echo "OK: description typo check passed"
fi

# 3. Forbidden use-case path pattern (Commands/ subfolder)
while IFS= read -r -d '' file; do
    rel="${file#"$REPO_ROOT"/}"
    line_no=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_no++)) || true
        if [[ "$line" =~ (Application/|Orders/)Commands/ ]]; then
            add_error "$rel:$line_no uses Commands/ subfolder. Use flat use-case folders (e.g. Orders/CreateOrder/)."
        fi
    done < "$file"
done < <(find "$SKILL_ROOT" -type f -name '*.md' -print0)

if [[ ${#errors[@]} -eq 0 ]]; then
    echo "OK: no Commands/ subfolder paths in examples"
fi

# 4. Required reference files
required_refs=(
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
    if [[ ! -f "$SKILL_ROOT/$ref" ]]; then
        add_error "Missing required file: skills/dotnet-clean-architecture/$ref"
    fi
done

if [[ ${#errors[@]} -eq 0 ]]; then
    echo "OK: all required reference files exist"
fi

echo ""

if [[ ${#warnings[@]} -gt 0 ]]; then
    echo "Warnings:"
    for warning in "${warnings[@]}"; do
        echo "  WARN: $warning"
    done
    echo ""
fi

if [[ ${#errors[@]} -gt 0 ]]; then
    echo "Validation failed:"
    for err in "${errors[@]}"; do
        echo "  ERROR: $err"
    done
    exit 1
fi

echo "Validation passed."
