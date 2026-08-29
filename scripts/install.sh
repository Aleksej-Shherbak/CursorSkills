#!/usr/bin/env bash
# Installs CursorSkills into ~/.cursor/skills/ via symlinks (or copy with --copy).
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

installed=()

for skill_path in "${skill_dirs[@]}"; do
    skill_name="$(basename "$skill_path")"
    target_path="$SKILLS_TARGET/$skill_name"

    if [[ -e "$target_path" || -L "$target_path" ]]; then
        if [[ "$COPY" == true ]]; then
            rm -rf "$target_path"
        elif [[ -L "$target_path" ]]; then
            rm "$target_path"
        else
            echo "Warning: skipping '$skill_name' — path already exists: $target_path (use --copy to replace)"
            continue
        fi
    fi

    if [[ "$COPY" == true ]]; then
        cp -R "$skill_path" "$target_path"
        echo "Copied: $skill_name -> $target_path"
    else
        ln -s "$skill_path" "$target_path"
        echo "Linked: $skill_name -> $target_path"
    fi

    installed+=("$skill_name")
done

echo ""
echo "Installed skills:"
for name in "${installed[@]}"; do
    echo "  - $name"
done

echo ""
echo "Restart Cursor to load the new skills."
echo "Use @dotnet-clean-architecture in Agent chat to invoke the skill."
