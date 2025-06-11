#!/usr/bin/env python3
"""
Analyze rattler-build recipes for anomalies and inconsistencies.
"""

import os
import yaml
import re
from pathlib import Path
from typing import Dict, List, Any, Optional
from urllib.parse import urlparse

class RecipeAnalyzer:
    def __init__(self, pkgs_dir: str):
        self.pkgs_dir = Path(pkgs_dir)
        self.anomalies = []
        self.recipes_checked = 0

    def analyze_all_recipes(self):
        """Analyze all recipe.yaml files in the pkgs directory."""
        recipe_files = list(self.pkgs_dir.glob("*/recipe.yaml"))

        print(f"Found {len(recipe_files)} recipe files to analyze...")
        print("=" * 60)

        for recipe_file in sorted(recipe_files):
            self.analyze_recipe(recipe_file)

        self.print_summary()

    def analyze_recipe(self, recipe_file: Path):
        """Analyze a single recipe file for anomalies."""
        package_name = recipe_file.parent.name
        self.recipes_checked += 1

        print(f"\nAnalyzing: {package_name}")
        print("-" * 40)

        try:
            with open(recipe_file, 'r') as f:
                content = f.read()

            # Check for YAML syntax issues
            try:
                recipe_data = yaml.safe_load(content)
            except yaml.YAMLError as e:
                self.add_anomaly(package_name, "YAML_SYNTAX", f"Invalid YAML syntax: {e}")
                return

            # Perform various checks
            self.check_required_fields(package_name, recipe_data, content)
            self.check_schema_version(package_name, recipe_data, content)
            self.check_package_section(package_name, recipe_data, content)
            self.check_source_section(package_name, recipe_data, content)
            self.check_build_section(package_name, recipe_data, content)
            self.check_requirements_section(package_name, recipe_data, content)
            self.check_tests_section(package_name, recipe_data, content)
            self.check_about_section(package_name, recipe_data, content)
            self.check_context_variables(package_name, recipe_data, content)
            self.check_formatting_consistency(package_name, content)

        except Exception as e:
            self.add_anomaly(package_name, "FILE_ERROR", f"Error reading file: {e}")

    def check_required_fields(self, package_name: str, recipe_data: dict, content: str):
        """Check for required top-level fields."""
        required_fields = ['schema_version', 'package', 'about']
        lines = content.split('\n')

        for field in required_fields:
            if field not in recipe_data:
                # Try to find where this field should be added (after existing top-level fields)
                line_num = self.find_insertion_point(lines, field)
                self.add_anomaly(package_name, "MISSING_FIELD", f"Missing required field: {field}", line_num)

    def check_schema_version(self, package_name: str, recipe_data: dict, content: str):
        """Check schema version."""
        if 'schema_version' in recipe_data:
            version = recipe_data['schema_version']
            if version != 1:
                line_num = self.find_field_line(content, 'schema_version')
                self.add_anomaly(package_name, "SCHEMA_VERSION", f"Unexpected schema version: {version}", line_num)

    def check_package_section(self, package_name: str, recipe_data: dict, content: str):
        """Check package section."""
        if 'package' not in recipe_data:
            return

        pkg = recipe_data['package']

        # Check required package fields
        if 'name' not in pkg:
            line_num = self.find_section_line(content, 'package')
            self.add_anomaly(package_name, "MISSING_PKG_NAME", "Missing package.name", line_num)
        elif pkg['name'] != package_name:
            # Allow for skeleton packages to have different names
            if not package_name.startswith('_skeleton'):
                line_num = self.find_field_line(content, 'name', section='package')
                self.add_anomaly(package_name, "NAME_MISMATCH",
                               f"Package name '{pkg['name']}' doesn't match directory '{package_name}'", line_num)

        if 'version' not in pkg:
            line_num = self.find_section_line(content, 'package')
            self.add_anomaly(package_name, "MISSING_VERSION", "Missing package.version", line_num)

    def check_source_section(self, package_name: str, recipe_data: dict, content: str):
        """Check source section."""
        if 'source' not in recipe_data:
            # Some packages might not have source (e.g., meta packages)
            return

        source = recipe_data['source']

        # Handle both single source and list of sources
        if isinstance(source, list):
            # List of sources
            for i, src in enumerate(source):
                self._check_single_source(package_name, src, content, i)
        else:
            # Single source
            self._check_single_source(package_name, source, content)

    def _check_single_source(self, package_name: str, source: dict, content: str, index: int = None):
        """Check a single source entry for required fields."""
        source_desc = f"source[{index}]" if index is not None else "source"

        # Skip if using git source (doesn't need url/sha256)
        if 'git' in source:
            return

        # Skip if using path source (local development)
        if 'path' in source:
            return

        # Skip conditional sources (if/then blocks)
        if 'if' in source and 'then' in source:
            # Check the 'then' part for path sources
            then_part = source.get('then', {})
            if isinstance(then_part, dict) and 'path' in then_part:
                return

        # Only check for URL/SHA256 if this is a download source
        needs_url_sha = True
        if isinstance(source, dict):
            # Check if this source has conditional path sources
            if 'if' in source and 'then' in source:
                then_part = source.get('then', {})
                if isinstance(then_part, dict) and ('path' in then_part or 'git' in then_part):
                    needs_url_sha = False

        if needs_url_sha:
            if 'url' not in source:
                line_num = self.find_section_line(content, 'source')
                self.add_anomaly(package_name, "MISSING_SOURCE_URL", f"Missing {source_desc}.url", line_num)

            if 'sha256' not in source:
                line_num = self.find_section_line(content, 'source')
                self.add_anomaly(package_name, "MISSING_SHA256", f"Missing {source_desc}.sha256", line_num)
            elif source['sha256'] and len(source['sha256']) != 64:
                line_num = self.find_field_line(content, 'sha256', section='source')
                self.add_anomaly(package_name, "INVALID_SHA256",
                               f"SHA256 hash has wrong length: {len(source['sha256'])}", line_num)


    def check_build_section(self, package_name: str, recipe_data: dict, content: str):
        """Check build section."""
        if 'build' not in recipe_data:
            return

        build = recipe_data['build']

        # Check for common build issues - removed build.number requirement
        if 'script' not in build and 'python' not in build:
            # Some builds might use other methods, but most should have a script
            pass

    def check_requirements_section(self, package_name: str, recipe_data: dict, content: str):
        """Check requirements section."""
        if 'requirements' not in recipe_data:
            return

        reqs = recipe_data['requirements']

        # Check for common requirement issues
        if 'run' in reqs and isinstance(reqs['run'], list):
            for req in reqs['run']:
                if isinstance(req, str) and req.strip() == '':
                    self.add_anomaly(package_name, "EMPTY_REQUIREMENT", "Empty requirement in run section")

        # Check for duplicate requirements
        for section in ['build', 'host', 'run']:
            if section in reqs and isinstance(reqs[section], list):
                req_list = reqs[section]
                seen_reqs = set()
                for i, req in enumerate(req_list):
                    if isinstance(req, str):
                        # Don't treat template functions as duplicates
                        if req.startswith('${{') and req.endswith('}}'):
                            # Template functions like ${{ compiler('c') }} and ${{ compiler('cxx') }} are different
                            req_normalized = req.strip()
                        else:
                            # For regular packages, get the base name without version constraints
                            req_normalized = req.split()[0]

                        if req_normalized in seen_reqs:
                            line_num = self.find_requirement_line(content, section, i)
                            self.add_anomaly(package_name, "DUPLICATE_REQUIREMENT",
                                           f"Duplicate requirement '{req_normalized}' in {section}", line_num)
                        seen_reqs.add(req_normalized)

    def check_tests_section(self, package_name: str, recipe_data: dict, content: str):
        """Check tests section."""
        if 'tests' not in recipe_data:
            line_num = self.find_insertion_point_after_requirements(content)
            self.add_anomaly(package_name, "NO_TESTS", "No tests section found", line_num)
            return

        tests = recipe_data['tests']
        if not tests or len(tests) == 0:
            line_num = self.find_section_line(content, 'tests')
            self.add_anomaly(package_name, "EMPTY_TESTS", "Tests section is empty", line_num)

    def check_about_section(self, package_name: str, recipe_data: dict, content: str):
        """Check about section."""
        if 'about' not in recipe_data:
            return

        about = recipe_data['about']

        # Check required about fields
        if 'license' not in about:
            line_num = self.find_section_line(content, 'about')
            self.add_anomaly(package_name, "MISSING_LICENSE", "Missing about.license", line_num)

        if 'summary' not in about:
            line_num = self.find_section_line(content, 'about')
            self.add_anomaly(package_name, "MISSING_SUMMARY", "Missing about.summary", line_num)

        # Check homepage URL format
        if 'homepage' in about:
            homepage = about['homepage']
            if not self.is_valid_url(homepage):
                line_num = self.find_field_line(content, 'homepage', section='about')
                self.add_anomaly(package_name, "INVALID_HOMEPAGE", f"Invalid homepage URL: {homepage}", line_num)

    def check_context_variables(self, package_name: str, recipe_data: dict, content: str):
        """Check context variable usage."""
        if 'context' not in recipe_data:
            return

        context = recipe_data['context']

        # Find all context variable references in the content
        context_refs = re.findall(r'\$\{\{\s*(\w+)\s*\}\}', content)

        # Check if all referenced variables are defined
        for var_ref in context_refs:
            if var_ref not in context:
                line_num = self.find_context_var_usage(content, var_ref)
                self.add_anomaly(package_name, "UNDEFINED_CONTEXT_VAR",
                               f"Context variable '{var_ref}' is used but not defined", line_num)

        # Check if all defined variables are used
        for var_name in context:
            var_pattern = f'\\$\\{{\\{{\\s*{var_name}\\s*\\}}\\}}'
            if not re.search(var_pattern, content):
                line_num = self.find_field_line(content, var_name, section='context')
                self.add_anomaly(package_name, "UNUSED_CONTEXT_VAR",
                               f"Context variable '{var_name}' is defined but not used", line_num)

    def check_formatting_consistency(self, package_name: str, content: str):
        """Check for formatting inconsistencies."""
        lines = content.split('\n')

        # Check for inconsistent indentation
        self._check_yaml_indentation(package_name, lines)

        # Check for trailing whitespace
        trailing_lines = [i for i, line in enumerate(lines, 1) if line.endswith(' ') or line.endswith('\t')]
        if trailing_lines:
            self.add_anomaly(package_name, "TRAILING_WHITESPACE", "Found trailing whitespace", trailing_lines[0])

    def _check_yaml_indentation(self, package_name: str, lines: list):
        """Check for truly inconsistent YAML indentation."""
        # Only flag obvious indentation problems that would break YAML parsing
        problematic_lines = []

        for i, line in enumerate(lines, 1):
            if not line.strip() or not line.startswith(' '):
                continue

            leading_spaces = len(line) - len(line.lstrip(' '))
            stripped_line = line.strip()

            # Skip comments - they can have any indentation
            if stripped_line.startswith('#'):
                continue

            # Flag only truly problematic cases:
            # 1. Odd number of spaces (not multiple of 2) - but only if it's not 1 space
            if leading_spaces % 2 != 0 and leading_spaces > 1:
                problematic_lines.append((i, leading_spaces, "odd indentation"))
                continue

            # 2. Only flag extremely obvious structural problems
            if i > 1 and leading_spaces > 0:
                # Find the most recent non-comment, non-empty line
                prev_line_idx = i - 2
                while prev_line_idx >= 0:
                    prev_line = lines[prev_line_idx]
                    if prev_line.strip() and not prev_line.strip().startswith('#'):
                        break
                    prev_line_idx -= 1

                if prev_line_idx >= 0:
                    prev_line = lines[prev_line_idx]
                    prev_indent = len(prev_line) - len(prev_line.lstrip(' '))
                    prev_content = prev_line.strip()

                    # Only flag if a non-multiline key has content at same or less indentation
                    if (prev_content.endswith(':') and
                        not prev_content.endswith(('|', '>', '|-', '>-')) and
                        not stripped_line.startswith('- ') and  # Allow list items
                        leading_spaces <= prev_indent):
                        problematic_lines.append((i, leading_spaces, "insufficient indentation after key"))
                        continue

        if problematic_lines:
            first_line, first_indent, reason = problematic_lines[0]
            self.add_anomaly(package_name, "INCONSISTENT_INDENTATION",
                           f"Indentation issue: {reason} at {first_indent} spaces", first_line)



    def is_valid_url(self, url: str) -> bool:
        """Check if URL has valid format."""
        try:
            result = urlparse(url)
            return all([result.scheme, result.netloc])
        except:
            return False

    def add_anomaly(self, package_name: str, anomaly_type: str, description: str, line_number: int = None):
        """Add an anomaly to the list."""
        self.anomalies.append({
            'package': package_name,
            'type': anomaly_type,
            'description': description,
            'line': line_number
        })
        line_info = f" (line {line_number})" if line_number else ""
        print(f"  ⚠️  {anomaly_type}: {description}{line_info}")

    def find_field_line(self, content: str, field_name: str, section: str = None) -> int:
        """Find the line number where a field is defined."""
        lines = content.split('\n')
        in_section = section is None

        for i, line in enumerate(lines, 1):
            if section and line.strip().startswith(f"{section}:"):
                in_section = True
                continue
            elif section and line.strip() and not line.startswith(' ') and not line.startswith('\t'):
                if in_section:
                    in_section = False

            if in_section and line.strip().startswith(f"{field_name}:"):
                return i

        return None

    def find_section_line(self, content: str, section_name: str) -> int:
        """Find the line number where a section starts."""
        lines = content.split('\n')
        for i, line in enumerate(lines, 1):
            if line.strip().startswith(f"{section_name}:"):
                return i
        return None

    def find_insertion_point(self, lines: list, field_name: str) -> int:
        """Find where a missing top-level field should be inserted."""
        # For top-level fields, insert after existing top-level fields
        for i, line in enumerate(lines, 1):
            if line.strip() and not line.startswith(' ') and not line.startswith('\t') and ':' in line:
                continue
            return max(1, i - 1)
        return 1

    def find_insertion_point_after_requirements(self, content: str) -> int:
        """Find insertion point after requirements section."""
        req_line = self.find_section_line(content, 'requirements')
        if req_line:
            lines = content.split('\n')
            # Find end of requirements section
            for i in range(req_line, len(lines)):
                if lines[i].strip() and not lines[i].startswith(' ') and not lines[i].startswith('\t'):
                    return i + 1
        return None

    def find_context_var_usage(self, content: str, var_name: str) -> int:
        """Find the first line where a context variable is used."""
        lines = content.split('\n')
        pattern = f'\\$\\{{\\{{\\s*{var_name}\\s*\\}}\\}}'
        for i, line in enumerate(lines, 1):
            if re.search(pattern, line):
                return i
        return None

    def find_requirement_line(self, content: str, section: str, index: int) -> int:
        """Find the line number of a specific requirement in a section."""
        lines = content.split('\n')
        in_requirements = False
        in_section = False
        req_count = 0

        for i, line in enumerate(lines, 1):
            if line.strip().startswith('requirements:'):
                in_requirements = True
                continue
            elif in_requirements and line.strip().startswith(f'{section}:'):
                in_section = True
                continue
            elif in_requirements and in_section:
                if line.strip().startswith('- '):
                    if req_count == index:
                        return i
                    req_count += 1
                elif line.strip() and not line.startswith(' ') and not line.startswith('\t'):
                    break

        return None

    def print_summary(self):
        """Print analysis summary."""
        print("\n" + "=" * 60)
        print("ANALYSIS SUMMARY")
        print("=" * 60)

        print(f"Total recipes analyzed: {self.recipes_checked}")
        print(f"Total anomalies found: {len(self.anomalies)}")

        if self.anomalies:
            # Group anomalies by type
            anomaly_types = {}
            for anomaly in self.anomalies:
                anomaly_type = anomaly['type']
                if anomaly_type not in anomaly_types:
                    anomaly_types[anomaly_type] = []
                anomaly_types[anomaly_type].append(anomaly)

            print("\nAnomalies by type:")
            for anomaly_type, anomalies in sorted(anomaly_types.items()):
                print(f"  {anomaly_type}: {len(anomalies)}")

            print("\nPackages with anomalies:")
            packages_with_issues = set(anomaly['package'] for anomaly in self.anomalies)
            for package in sorted(packages_with_issues):
                package_anomalies = [a for a in self.anomalies if a['package'] == package]
                print(f"  {package}: {len(package_anomalies)} issues")

        else:
            print("\n✅ No anomalies found! All recipes look good.")

        print("\nDone!")

def main():
    """Main function."""
    script_dir = Path(__file__).parent.parent
    pkgs_dir = script_dir / "pkgs"

    if not pkgs_dir.exists():
        print(f"Error: pkgs directory not found at {pkgs_dir}")
        return

    analyzer = RecipeAnalyzer(pkgs_dir)
    analyzer.analyze_all_recipes()

if __name__ == "__main__":
    main()
