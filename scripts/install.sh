#!/usr/bin/env bash
# Installs CursorSkills into ~/.cursor/skills/ via symlinks (or copy with --copy).
# Reinstalls when source version is higher than installed, or installed has no version.
set -euo pipefail

COPY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --copy) COPY=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SOURCE="$REPO_ROOT/skills"
SKILLS_TARGET="${HOME}/.cursor/skills"

get_skill_version() {
    local skill_md="$1"

    if [[ ! -f "$skill_md" ]]; then
        echo ""
        return
    fi

    local version
    version="$(grep -E '^version:[[:space:]]*[0-9]+(\.[0-9]+)*[[:space:]]*$' "$skill_md" | head -n 1 | sed -E 's/^version:[[:space:]]*//')"
    echo "$version"
}

format_version() {
    local version="$1"
    if [[ -z "$version" ]]; then
        echo "none"
    else
        echo "$version"
    fi
}

version_gt() {
    local left="$1"
    local right="$2"

    if [[ "$(printf '%s\n' "$left" "$right" | sort -V | head -n 1)" != "$left" ]]; then
        return 0
    fi

    if [[ "$left" == "$right" ]]; then
        return 1
    fi

    return 1
}

should_reinstall() {
    local source_version="$1"
    local installed_version="$2"

    if [[ -z "$source_version" ]]; then
        echo "Error: source SKILL.md must contain a version field (e.g. version: 1.0.0)." >&2
        exit 1
    fi

    if [[ -z "$installed_version" ]]; then
        return 0
    fi

    if version_gt "$source_version" "$installed_version"; then
        return 0
    fi

    return 1
}

remove_skill_installation() {
    local target_path="$1"

    if [[ -e "$target_path" || -L "$target_path" ]]; then
        rm -rf "$target_path"
        echo "Removed existing installation: $target_path"
    fi
}

if [[ ! -d "$SKILLS_SOURCE" ]]; then
    echo "Error: skills directory not found: $SKILLS_SOURCE" >&2
    exit 1
fi

mkdir -p "$SKILLS_TARGET"

shopt -s nullglob
skill_dirs=("$SKILLS_SOURCE"/*/)

if [[ ${#skill_dirs[@]} -eq 0 ]]; then
    echo "Warning: no skills found in $SKILLS_SOURCE"
    exit 0
fi

installed_names=()
installed_versions=()
skipped_names=()
skipped_current=()
skipped_source=()

for skill_path in "${skill_dirs[@]}"; do
    skill_name="$(basename "$skill_path")"
    target_path="$SKILLS_TARGET/$skill_name"
    source_skill_md="$skill_path/SKILL.md"
    target_skill_md="$target_path/SKILL.md"

    source_version="$(get_skill_version "$source_skill_md")"
    installed_version=""

    if [[ -e "$target_path" || -L "$target_path" ]]; then
        installed_version="$(get_skill_version "$target_skill_md")"
    fi

    if ! should_reinstall "$source_version" "$installed_version"; then
        skipped_names+=("$skill_name")
        skipped_current+=("$(format_version "$installed_version")")
        skipped_source+=("$(format_version "$source_version")")
        echo "Skipping '$skill_name' - installed $(format_version "$installed_version") >= source $(format_version "$source_version")"
        continue
    fi

    if [[ -e "$target_path" || -L "$target_path" ]]; then
        if [[ -z "$installed_version" ]]; then
            echo "Upgrading '$skill_name' - installed version missing, source $(format_version "$source_version")"
        else
            echo "Upgrading '$skill_name' - $(format_version "$installed_version") -> $(format_version "$source_version")"
        fi

        remove_skill_installation "$target_path"
    else
        echo "Installing '$skill_name' v$(format_version "$source_version")"
    fi

    if [[ "$COPY" == true ]]; then
        cp -R "$skill_path" "$target_path"
        echo "Copied: $skill_name v$(format_version "$source_version") -> $target_path"
    else
        ln -s "$skill_path" "$target_path"
        echo "Linked: $skill_name v$(format_version "$source_version") -> $target_path"
    fi

    installed_names+=("$skill_name")
    installed_versions+=("$(format_version "$source_version")")
done

echo ""

if [[ ${#installed_names[@]} -gt 0 ]]; then
    echo "Installed skills:"
    for i in "${!installed_names[@]}"; do
        echo "  - ${installed_names[$i]} v${installed_versions[$i]}"
    done
fi

if [[ ${#skipped_names[@]} -gt 0 ]]; then
    echo ""
    echo "Skipped (already up to date):"
    for i in "${!skipped_names[@]}"; do
        echo "  - ${skipped_names[$i]} (installed v${skipped_current[$i]}, source v${skipped_source[$i]})"
    done
fi

echo ""
echo "Restart Cursor to load updated skills."
echo "Use /dotnet-clean-architecture or /dotnet-tester in Agent chat to invoke skills."
