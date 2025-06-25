#!/usr/bin/env python3
"""
YAML utilities for consistent formatting across all meso-forge scripts.

This module provides standardized YAML loading and dumping functions to ensure
consistent formatting of recipe.yaml files across all tools in the project.
"""

from pathlib import Path
from typing import Any, Dict, Union
import sys

try:
    from ruamel.yaml import YAML
    from ruamel.yaml.error import YAMLError
    HAS_RUAMEL_YAML = True
except ImportError:
    import yaml
    from yaml import YAMLError
    HAS_RUAMEL_YAML = False


def create_yaml_processor():
    """Create a configured YAML processor with consistent formatting settings."""
    if HAS_RUAMEL_YAML:
        yaml_processor = YAML()
        # Preserve original formatting characteristics
        yaml_processor.preserve_quotes = True
        yaml_processor.width = 4096  # Prevent unwanted line wrapping
        yaml_processor.map_indent = 2  # 2 spaces for mapping indentation
        yaml_processor.sequence_indent = 4  # 4 spaces for sequence indentation
        yaml_processor.sequence_dash_offset = 2  # 2 spaces before dash
        yaml_processor.default_flow_style = False
        yaml_processor.allow_unicode = True
        yaml_processor.encoding = 'utf-8'
        # Preserve comments and structure
        yaml_processor.preserve_quotes = True
        return yaml_processor
    else:
        return None


def load_yaml(file_path: Union[str, Path]) -> Dict[str, Any]:
    """
    Load YAML file with consistent parsing.

    Args:
        file_path: Path to YAML file

    Returns:
        Parsed YAML content as dictionary

    Raises:
        YAMLError: If YAML parsing fails
        FileNotFoundError: If file doesn't exist
    """
    file_path = Path(file_path)

    if not file_path.exists():
        raise FileNotFoundError(f"YAML file not found: {file_path}")

    with open(file_path, 'r', encoding='utf-8') as f:
        if HAS_RUAMEL_YAML:
            yaml_processor = create_yaml_processor()
            return yaml_processor.load(f)
        else:
            return yaml.safe_load(f)


def dump_yaml(data: Dict[str, Any], file_path: Union[str, Path]) -> None:
    """
    Write YAML file with consistent formatting.

    Args:
        data: Data to write as YAML
        file_path: Path where to write YAML file

    Raises:
        YAMLError: If YAML serialization fails
    """
    file_path = Path(file_path)

    # Ensure parent directory exists
    file_path.parent.mkdir(parents=True, exist_ok=True)

    with open(file_path, 'w', encoding='utf-8') as f:
        if HAS_RUAMEL_YAML:
            yaml_processor = create_yaml_processor()
            yaml_processor.dump(data, f)
        else:
            # Fallback to standard yaml with consistent formatting
            yaml.dump(
                data,
                f,
                default_flow_style=False,
                allow_unicode=True,
                indent=2,
                sort_keys=False,
                width=4096
            )


def dump_yaml_string(data: Dict[str, Any]) -> str:
    """
    Convert data to YAML string with consistent formatting.

    Args:
        data: Data to convert to YAML string

    Returns:
        YAML formatted string
    """
    if HAS_RUAMEL_YAML:
        from io import StringIO
        yaml_processor = create_yaml_processor()
        stream = StringIO()
        yaml_processor.dump(data, stream)
        return stream.getvalue()
    else:
        return yaml.dump(
            data,
            default_flow_style=False,
            allow_unicode=True,
            indent=2,
            sort_keys=False,
            width=4096
        )


def validate_yaml_format(file_path: Union[str, Path]) -> bool:
    """
    Validate that a YAML file can be parsed correctly.

    Args:
        file_path: Path to YAML file to validate

    Returns:
        True if valid YAML, False otherwise
    """
    try:
        load_yaml(file_path)
        return True
    except (YAMLError, FileNotFoundError, Exception):
        return False


def format_yaml_file(file_path: Union[str, Path], backup: bool = True) -> bool:
    """
    Reformat a YAML file to ensure consistent formatting.

    Args:
        file_path: Path to YAML file to reformat
        backup: Whether to create a backup before reformatting

    Returns:
        True if successfully reformatted, False otherwise
    """
    file_path = Path(file_path)

    try:
        # Create backup if requested
        if backup:
            backup_path = file_path.with_suffix(f"{file_path.suffix}.backup")
            backup_path.write_text(file_path.read_text(encoding='utf-8'), encoding='utf-8')

        # Load and re-save with consistent formatting
        data = load_yaml(file_path)
        dump_yaml(data, file_path)
        return True

    except Exception as e:
        print(f"Error formatting YAML file {file_path}: {e}", file=sys.stderr)
        return False


def main():
    """CLI interface for YAML formatting utilities."""
    import argparse

    parser = argparse.ArgumentParser(
        description="YAML formatting utilities for meso-forge",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --format pkgs/fd/recipe.yaml          # Format single file
  %(prog)s --validate pkgs/*/recipe.yaml         # Validate multiple files
  %(prog)s --format-all                          # Format all recipe files
        """
    )

    parser.add_argument('--format', metavar='FILE', nargs='+',
                        help='Format specified YAML files')
    parser.add_argument('--validate', metavar='FILE', nargs='+',
                        help='Validate specified YAML files')
    parser.add_argument('--format-all', action='store_true',
                        help='Format all recipe.yaml files in pkgs/')
    parser.add_argument('--no-backup', action='store_true',
                        help='Skip creating backup files when formatting')

    args = parser.parse_args()

    if args.format:
        for file_path in args.format:
            print(f"Formatting {file_path}...")
            if format_yaml_file(file_path, backup=not args.no_backup):
                print(f"✅ Successfully formatted {file_path}")
            else:
                print(f"❌ Failed to format {file_path}")

    elif args.validate:
        all_valid = True
        for file_path in args.validate:
            if validate_yaml_format(file_path):
                print(f"✅ {file_path} is valid YAML")
            else:
                print(f"❌ {file_path} has YAML errors")
                all_valid = False
        sys.exit(0 if all_valid else 1)

    elif args.format_all:
        pkgs_dir = Path("pkgs")
        if not pkgs_dir.exists():
            print("Error: pkgs/ directory not found")
            sys.exit(1)

        recipe_files = list(pkgs_dir.glob("*/recipe.yaml"))
        print(f"Found {len(recipe_files)} recipe files to format")

        success_count = 0
        for recipe_file in recipe_files:
            print(f"Formatting {recipe_file}...")
            if format_yaml_file(recipe_file, backup=not args.no_backup):
                success_count += 1

        print(f"✅ Successfully formatted {success_count}/{len(recipe_files)} files")

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
