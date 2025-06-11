#!/usr/bin/env python3
"""
Generate and maintain readme.adoc files for all packages based on their recipe.yaml files.
Ensures each package has a consistent README that matches its recipe while preserving custom content.
"""

import os
import yaml
import re
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime


class ReadmeGenerator:
    def __init__(self, pkgs_dir: str):
        self.pkgs_dir = Path(pkgs_dir)
        self.generated_count = 0
        self.updated_count = 0
        self.skipped_count = 0

    def generate_all_readmes(self):
        """Generate or update README files for all packages."""
        recipe_files = list(self.pkgs_dir.glob("*/recipe.yaml"))

        print(f"Found {len(recipe_files)} packages to process...")
        print("=" * 60)

        for recipe_file in sorted(recipe_files):
            self.process_package(recipe_file)

        self.print_summary()

    def process_package(self, recipe_file: Path):
        """Process a single package to generate/update its README."""
        package_dir = recipe_file.parent
        package_name = package_dir.name
        readme_file = package_dir / "readme.adoc"

        print(f"Processing: {package_name}")

        try:
            with open(recipe_file, 'r') as f:
                recipe_content = f.read()

            # Parse YAML
            recipe_data = yaml.safe_load(recipe_content)

            # Generate README content (raw, without markers)
            generated_content = self.generate_readme_content(package_name, recipe_data)

            # Check if README needs updating
            if readme_file.exists():
                with open(readme_file, 'r') as f:
                    existing_content = f.read()

                # Parse existing content to separate custom and generated sections
                custom_content, existing_generated = self.parse_existing_readme(existing_content)

                # Check if generated content has changed
                if existing_generated.strip() == generated_content.strip():
                    print(f"  ⏭️  README is up to date")
                    self.skipped_count += 1
                    return
                else:
                    # Merge custom content with new generated content
                    final_content = self.merge_readme_content(custom_content, generated_content)
                    print(f"  📝 Updating README (preserving custom content)")
                    self.updated_count += 1
            else:
                # For new files, wrap with markers
                final_content = self.merge_readme_content("", generated_content)
                print(f"  ✨ Creating new README")
                self.generated_count += 1

            # Write README file
            with open(readme_file, 'w') as f:
                f.write(final_content)

        except Exception as e:
            print(f"  ❌ Error processing {package_name}: {e}")

    def parse_existing_readme(self, content: str) -> Tuple[str, str]:
        """Parse existing README to separate custom content from auto-generated content."""
        start_marker = "// AUTO-GENERATED CONTENT START"
        end_marker = "// AUTO-GENERATED CONTENT END"

        # Look for markers in the content
        start_idx = content.find(start_marker)
        end_idx = content.find(end_marker)

        if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
            # Extract custom content (everything after the generated section)
            custom_after = content[end_idx + len(end_marker):].lstrip()
            custom_content = custom_after.strip() if custom_after else ""

            # Extract existing generated content (excluding markers)
            generated_content = content[start_idx + len(start_marker):end_idx].strip()

            return custom_content, generated_content
        else:
            # No markers found - everything after the title is custom content
            lines = content.split('\n')
            custom_start_idx = 0

            # Find the title line and skip it
            for i, line in enumerate(lines):
                if line.startswith('=') and not line.startswith('=='):  # AsciiDoc title
                    custom_start_idx = i + 1
                    break

            # Everything after the title is custom content
            custom_lines = lines[custom_start_idx:]
            custom_content = '\n'.join(custom_lines).strip()

            return custom_content, ""

    def merge_readme_content(self, custom_content: str, generated_content: str) -> str:
        """Merge custom content with generated content using markers."""
        parts = []

        # Add the auto-generated section with markers (includes title)
        parts.append("// AUTO-GENERATED CONTENT START")
        parts.append(generated_content.strip())
        parts.append("// AUTO-GENERATED CONTENT END")

        # Add custom content after the generated content if it exists
        if custom_content:
            parts.append(custom_content.strip())

        return '\n\n'.join(parts) + '\n'

    def generate_readme_content(self, package_name: str, recipe_data: dict) -> str:
        """Generate README content based on recipe data."""

        # Extract basic info
        pkg_info = recipe_data.get('package', {})
        about_info = recipe_data.get('about', {})
        context_info = recipe_data.get('context', {})
        source_info = recipe_data.get('source', {})
        requirements = recipe_data.get('requirements', {})

        pkg_display_name = pkg_info.get('name', package_name)
        version = self._resolve_template(pkg_info.get('version', 'unknown'), context_info)
        summary = about_info.get('summary', 'Package description not available')
        description = about_info.get('description', '').strip()
        homepage = about_info.get('homepage', '')
        repository = about_info.get('repository', '')
        documentation = about_info.get('documentation', '')
        license_name = about_info.get('license', 'License not specified')

        # Build content
        content = []

        # Title and version
        if package_name.startswith('_skeleton'):
            content.append(f"= {pkg_display_name} (Template)")
            content.append("")
            content.append("This is a package template/skeleton for creating new rattler-build recipes.")
        else:
            content.append(f"= {pkg_display_name}")
            if version != 'unknown':
                content.append(f":version: {version}")
            content.append("")

        # Summary
        content.append(summary)
        content.append("")

        # Description
        if description:
            content.append("== Description")
            content.append("")
            # Clean up description formatting
            desc_lines = description.split('\n')
            cleaned_desc = []
            for line in desc_lines:
                cleaned_line = line.strip()
                if cleaned_line:
                    cleaned_desc.append(cleaned_line)
            content.append(' '.join(cleaned_desc))
            content.append("")

        # Links section
        links = []
        if homepage:
            links.append(f"* Homepage: {homepage}")
        if repository and repository != homepage:
            links.append(f"* Repository: {repository}")
        if documentation and documentation != homepage:
            links.append(f"* Documentation: {documentation}")

        if links:
            content.append("== Links")
            content.append("")
            content.extend(links)
            content.append("")

        # Package Information
        content.append("== Package Information")
        content.append("")
        content.append(f"* **License**: {license_name}")

        if version != 'unknown':
            content.append(f"* **Version**: {version}")

        # Add platform info if available
        build_info = recipe_data.get('build', {})
        if build_info.get('noarch'):
            content.append(f"* **Architecture**: No-architecture (pure {build_info['noarch']})")

        content.append("")

        # Requirements
        if requirements:
            content.append("== Requirements")
            content.append("")

            for req_type in ['host', 'run', 'build']:
                if req_type in requirements and requirements[req_type]:
                    reqs = requirements[req_type]
                    if isinstance(reqs, list) and reqs:
                        content.append(f"=== {req_type.title()} Requirements")
                        content.append("")
                        for req in reqs:
                            if isinstance(req, str):
                                # Clean up template variables for display
                                clean_req = self._clean_requirement_for_display(req)
                                content.append(f"* {clean_req}")
                            elif isinstance(req, dict) and 'if' in req:
                                # Handle conditional requirements
                                condition = req.get('if', '')
                                then_reqs = req.get('then', [])
                                if isinstance(then_reqs, list):
                                    content.append(f"* (if {condition}):")
                                    for then_req in then_reqs:
                                        if isinstance(then_req, str):
                                            clean_req = self._clean_requirement_for_display(then_req)
                                            content.append(f"  ** {clean_req}")
                        content.append("")

        # Installation
        content.append("== Installation")
        content.append("")
        content.append("This package is built using rattler-build and can be installed using mamba or conda:")
        content.append("")
        content.append("```bash")
        content.append(f"mamba install -c meso-forge {pkg_display_name}")
        content.append("```")
        content.append("")

        # Maintainers
        extra_info = recipe_data.get('extra', {})
        maintainers = extra_info.get('recipe-maintainers', [])
        if maintainers:
            content.append("== Maintainers")
            content.append("")
            for maintainer in maintainers:
                content.append(f"* {maintainer}")
            content.append("")

        # Footer
        content.append("---")
        content.append("")
        content.append(f"_This README was auto-generated from the recipe.yaml file._")
        content.append("")
        content.append(f"_Last updated: {datetime.now().strftime('%Y-%m-%d')}_")

        return '\n'.join(content)

    def _resolve_template(self, value: str, context: dict) -> str:
        """Resolve simple template variables."""
        if not isinstance(value, str):
            return str(value)

        # Simple template resolution for display
        pattern = r'\$\{\{\s*(\w+)\s*\}\}'

        def replace_var(match):
            var_name = match.group(1)
            return str(context.get(var_name, f"${{{{{var_name}}}}}"))

        return re.sub(pattern, replace_var, value)

    def _clean_requirement_for_display(self, req: str) -> str:
        """Clean up requirement strings for display in README."""
        # Remove template function calls for cleaner display
        if req.startswith('${{ compiler('):
            if "'c'" in req:
                return "C compiler"
            elif "'cxx'" in req:
                return "C++ compiler"
            elif "'fortran'" in req:
                return "Fortran compiler"
            elif "'go'" in req:
                return "Go compiler"
            else:
                return "Compiler"
        elif req.startswith('${{ stdlib('):
            return "Standard library"
        elif req.startswith('${{') and req.endswith('}}'):
            # Keep other template variables as-is but make them readable
            return req.replace('${{', '').replace('}}', '').strip()
        else:
            return req

    def print_summary(self):
        """Print generation summary."""
        print("\n" + "=" * 60)
        print("README GENERATION SUMMARY")
        print("=" * 60)

        total_processed = self.generated_count + self.updated_count + self.skipped_count
        print(f"Total packages processed: {total_processed}")
        print(f"New READMEs created: {self.generated_count}")
        print(f"READMEs updated: {self.updated_count}")
        print(f"READMEs skipped (up to date): {self.skipped_count}")

        if self.generated_count > 0 or self.updated_count > 0:
            print(f"\n✅ Successfully processed {self.generated_count + self.updated_count} README files")

        print("\nDone!")


def main():
    """Main function."""
    script_dir = Path(__file__).parent.parent
    pkgs_dir = script_dir / "pkgs"

    if not pkgs_dir.exists():
        print(f"Error: pkgs directory not found at {pkgs_dir}")
        return

    generator = ReadmeGenerator(pkgs_dir)
    generator.generate_all_readmes()


if __name__ == "__main__":
    main()
