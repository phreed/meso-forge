#!/usr/bin/env python3
"""
Fix inconsistent YAML indentation in rattler-build recipe files.
Standardizes all recipe.yaml files to use 2-space indentation.
"""

import os
import re
from pathlib import Path
from typing import List


def fix_yaml_indentation(content: str) -> str:
    """
    Fix YAML indentation to use consistent 2-space indentation.
    Uses a stack-based approach to track indentation context.
    """
    lines = content.split('\n')
    fixed_lines = []
    indent_stack = [0]  # Stack to track indentation levels

    for line in lines:
        if not line.strip():  # Empty line
            fixed_lines.append('')
            continue

        # Count leading spaces
        leading_spaces = len(line) - len(line.lstrip(' '))
        stripped_line = line.lstrip()

        if leading_spaces == 0:  # Top-level keys
            indent_stack = [0]
            fixed_lines.append(line)
        else:
            # Determine the correct indentation level
            if stripped_line.startswith('- '):  # List item
                # List items should be at the same level as their parent or one level deeper
                if leading_spaces > indent_stack[-1]:
                    # New list, one level deeper than current
                    new_level = len(indent_stack)
                    indent_stack.append(new_level * 2)
                elif leading_spaces == indent_stack[-1]:
                    # Same level list item
                    new_level = len(indent_stack) - 1
                else:
                    # Pop stack until we find appropriate level
                    while len(indent_stack) > 1 and leading_spaces < indent_stack[-1]:
                        indent_stack.pop()
                    new_level = len(indent_stack) - 1
            else:
                # Regular key-value pairs
                if leading_spaces > indent_stack[-1]:
                    # Deeper level
                    new_level = len(indent_stack)
                    indent_stack.append(new_level * 2)
                elif leading_spaces == indent_stack[-1]:
                    # Same level
                    new_level = len(indent_stack) - 1
                else:
                    # Pop stack until we find appropriate level
                    while len(indent_stack) > 1 and leading_spaces < indent_stack[-1]:
                        indent_stack.pop()
                    new_level = len(indent_stack) - 1

            # Create properly indented line with 2 spaces per level
            proper_indent = '  ' * new_level
            fixed_line = proper_indent + stripped_line
            fixed_lines.append(fixed_line)

    return '\n'.join(fixed_lines)


def remove_trailing_whitespace(content: str) -> str:
    """Remove trailing whitespace from all lines."""
    lines = content.split('\n')
    cleaned_lines = [line.rstrip() for line in lines]
    return '\n'.join(cleaned_lines)


def fix_recipe_file(recipe_path: Path) -> bool:
    """
    Fix indentation and trailing whitespace in a single recipe file.
    Returns True if changes were made.
    """
    try:
        with open(recipe_path, 'r', encoding='utf-8') as f:
            original_content = f.read()

        # Fix indentation
        fixed_content = fix_yaml_indentation(original_content)

        # Remove trailing whitespace
        fixed_content = remove_trailing_whitespace(fixed_content)

        # Check if changes were made
        if fixed_content != original_content:
            with open(recipe_path, 'w', encoding='utf-8') as f:
                f.write(fixed_content)
            return True

        return False

    except Exception as e:
        print(f"Error processing {recipe_path}: {e}")
        return False


def main():
    """Main function to fix indentation in all recipe files."""
    script_dir = Path(__file__).parent.parent
    pkgs_dir = script_dir / "pkgs"

    if not pkgs_dir.exists():
        print(f"Error: pkgs directory not found at {pkgs_dir}")
        return

    recipe_files = list(pkgs_dir.glob("*/recipe.yaml"))

    if not recipe_files:
        print("No recipe.yaml files found!")
        return

    print(f"Found {len(recipe_files)} recipe files to process...")
    print("=" * 60)

    fixed_count = 0

    for recipe_file in sorted(recipe_files):
        package_name = recipe_file.parent.name
        print(f"Processing: {package_name}")

        if fix_recipe_file(recipe_file):
            print(f"  ✅ Fixed indentation and whitespace")
            fixed_count += 1
        else:
            print(f"  ⏭️  No changes needed")

    print("\n" + "=" * 60)
    print(f"Summary: Fixed {fixed_count} out of {len(recipe_files)} recipe files")

    if fixed_count > 0:
        print("\nRecommendation: Run 'pixi run analyze-recipes' to verify the fixes.")


if __name__ == "__main__":
    main()
