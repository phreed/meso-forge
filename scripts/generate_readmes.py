#!/usr/bin/env python3
"""
Generate and maintain readme.adoc files for all packages based on their recipe.yaml files.
Ensures each package has a consistent README that matches its recipe while preserving custom content.
"""

import yaml
import re
from pathlib import Path
import typer
from typing import Tuple, Optional
from datetime import datetime


class ReadmeGenerator:
    def __init__(self, pkgs_dir: Path):
        self.pkgs_dir = pkgs_dir
        self.generated_count = 0
        self.updated_count = 0
        self.skipped_count = 0

    def generate_all_readmes(self):
        """Generate or update README files for all packages."""
        recipe_files = list(self.pkgs_dir.glob("*/recipe.yaml"))

        print(f"Found {len(recipe_files)} packages to process...")
        print("=" * 60)

        for recipe_file in sorted(recipe_files):
            self.generate_readme(recipe_file)

        self.print_summary()

    def generate_readme(self, recipe_file: Path):
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
                    print("  ⏭️  README is up to date")
                    self.skipped_count += 1
                    return
                else:
                    # Merge custom content with new generated content
                    final_content = self.merge_readme_content(custom_content, generated_content)
                    print("  📝 Updating README (preserving custom content)")
                    self.updated_count += 1
            else:
                # For new files, wrap with markers
                final_content = self.merge_readme_content("", generated_content)
                print("  ✨ Creating new README")
                self.generated_count += 1

            # Write README file
            with open(readme_file, 'w') as f:
                f.write(final_content)

        except Exception as e:
            print(f"  ❌ Error processing {package_name}: {e}")

    def parse_existing_readme(self, content: str) -> Tuple[str, str]:
        """Parse existing README to separate custom content from generated content."""
        start_marker = "// GENERATED CONTENT START"
        end_marker = "// GENERATED CONTENT END"

        # Look for markers in the content
        start_idx = content.find(start_marker)
        end_idx = content.find(end_marker)

        if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
            # Extract custom content (everything after the generated section)
            custom_after = content[end_idx + len(end_marker):].lstrip()
            custom_content = custom_after.strip() if custom_after else ""

            # Extract existing generated content - need to reconstruct with title and attributes
            lines = content.split('\n')
            title_and_attrs = []

            # Find title and attributes at the beginning
            for i, line in enumerate(lines):
                if line.startswith('=') and not line.startswith('=='):
                    # Found title
                    title_and_attrs.append(line)
                elif line.startswith(':') and ':' in line[1:] and len(title_and_attrs) > 0:
                    # AsciiDoc attribute after title
                    title_and_attrs.append(line)
                elif line.strip() == '' and len(title_and_attrs) > 0:
                    # Empty line after title/attributes
                    title_and_attrs.append(line)
                elif len(title_and_attrs) > 0:
                    # First non-attribute line, stop collecting
                    break

            # Get content between markers
            generated_between_markers = content[start_idx + len(start_marker):end_idx].strip()

            # Reconstruct full generated content (title + attributes + content between markers)
            title_part = '\n'.join(title_and_attrs) if title_and_attrs else ""
            if title_part and generated_between_markers:
                generated_content = title_part + '\n\n' + generated_between_markers
            elif title_part:
                generated_content = title_part
            else:
                generated_content = generated_between_markers

            return custom_content, generated_content
        else:
            # No markers found - everything after the title is custom content
            lines = content.split('\n')
            custom_start_idx = 0

            # Find the title line and any attributes, skip them
            for i, line in enumerate(lines):
                if line.startswith('=') and not line.startswith('=='):  # AsciiDoc title
                    # Skip title and any following attributes
                    j = i + 1
                    while j < len(lines):
                        if lines[j].startswith(':') and ':' in lines[j][1:]:
                            # Skip attribute line
                            j += 1
                        elif lines[j].strip() == '':
                            # Skip empty line after attributes
                            j += 1
                        else:
                            # First non-attribute line
                            break
                    custom_start_idx = j
                    break

            # Everything after the title and attributes is custom content
            custom_lines = lines[custom_start_idx:]
            custom_content = '\n'.join(custom_lines).strip()

            return custom_content, ""

    def merge_readme_content(self, custom_content: str, generated_content: str) -> str:
        """Merge custom content with generated content using markers."""
        # Split generated content to separate title and attributes from rest
        generated_lines = generated_content.strip().split('\n')
        title_and_attrs = []
        rest_content = []

        title_found = False
        for i, line in enumerate(generated_lines):
            if line.startswith('=') and not line.startswith('==') and not title_found:
                # Found title line
                title_found = True
                title_and_attrs.append(line)
            elif title_found and line.startswith(':') and ':' in line[1:]:
                # AsciiDoc attribute/variable (e.g., :version: 1.0)
                title_and_attrs.append(line)
            elif title_found and line.strip() == '':
                # Empty line after title/attributes
                title_and_attrs.append(line)
                # Check if this is the end of title section
                if i + 1 < len(generated_lines) and not generated_lines[i + 1].startswith(':'):
                    rest_content = generated_lines[i+1:]
                    break
            elif title_found:
                # First non-attribute line after title
                rest_content = generated_lines[i:]
                break

        parts = []

        # Title and attributes must be first (no content before them in AsciiDoc)
        if title_and_attrs:
            parts.append('\n'.join(title_and_attrs))

        # Add the rest of generated content with markers
        parts.append("// GENERATED CONTENT START")
        if rest_content:
            parts.append('\n'.join(rest_content).strip())
        parts.append("// GENERATED CONTENT END")

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
        content.append("[source,bash]")
        content.append("----")
        content.append(f"pixi global install -c meso-forge {pkg_display_name}")
        content.append("----")
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
        content.append("_This portion of the README was generated from the recipe.yaml file._")
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

def main(
    base_dir: Path = typer.Option(Path(__file__).parent.parent, "--base-dir",
        help="Base directory for the project"),
    pkg_dir: Optional[str] = typer.Option("pkgs", "--pkg-dir",
        help="Directory containing the recipe packages"),
    recipe: Optional[str] = typer.Option(None, "--recipe",
        help="Name of a single recipe to analyze")
):
    """
    Construct a readme.adoc file for the recipe
    """
    if base_dir is None:
        print(f"Error: base_dir is not set properly {base_dir}")
        raise typer.Exit(1)
    if not base_dir.exists():
        print(f"Error: base_dir does not exist {base_dir}")
        raise typer.Exit(1)
    if not base_dir.is_dir():
        print(f"Error: base_dir is not a directory {base_dir}")
        raise typer.Exit(1)

    pkgs_dir = base_dir / pkg_dir

    if not pkgs_dir.exists():
        print(f"Error: pkgs directory not found at {pkgs_dir}")
        raise typer.Exit(1)

    if not pkgs_dir.exists():
        print(f"Error: pkgs directory not found at {pkgs_dir}")
        return

    generator = ReadmeGenerator(pkgs_dir)

    if recipe:
        recipe_path = pkgs_dir / recipe / "recipe.yaml"
        print (f"Generate a single readme {recipe_path}")
        if not recipe_path.exists():
            print(f"Error: Recipe file not found at {recipe_path}")
            raise typer.Exit(1)
        generator.generate_readme(recipe_path)
        generator.print_summary()
    else:
        print ("Generate all recipes (default behavior)")
        generator.generate_all_readmes()

if __name__ == "__main__":
    typer.run(main)
