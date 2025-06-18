#!/usr/bin/env python3
"""
Unified version control script for meso-forge packages.

This script combines and replaces the functionality of both check_updates.py and
update_versions.py, providing a comprehensive package version management solution
using py-rattler for intelligent conda-forge integration.

Features:
- Check package versions across conda-forge and upstream sources
- Update recipe files with new versions and SHA256 hashes
- Dry-run mode to preview changes before applying them
- Support for both individual packages and bulk operations
- JSON output for programmatic usage
- Conda-forge availability checking

This unified script supersedes:
- check_updates.py (checking functionality with user-friendly interface)
- update_versions.py (core update functionality and version detection)

Usage:
    python version_ctl.py --help
    python version_ctl.py --all                    # Check all packages
    python version_ctl.py --package fd             # Check specific package
    python version_ctl.py --conda-forge-only       # Only check conda-forge status
    python version_ctl.py --dry-run --all          # Preview what would be updated
    python version_ctl.py --update --all           # Actually update recipe files
    python version_ctl.py --newer-only             # Show only packages with updates
    python version_ctl.py --json --all             # JSON output for automation
"""

import argparse
import asyncio
import hashlib
import os
import sys
import tempfile
import yaml
import requests
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, List, Dict, Any, Tuple
import semver

# Import py-rattler components
try:
    from rattler import fetch_repo_data, Channel, Platform, MatchSpec
except ImportError as e:
    print(f"Error importing py-rattler: {e}")
    print("Please install py-rattler: pixi add py-rattler")
    sys.exit(1)


@dataclass
class UpdateStats:
    """Track statistics for the update process."""
    total_packages: int = 0
    packages_on_conda_forge: int = 0
    packages_not_on_conda_forge: int = 0
    packages_updated: int = 0
    packages_up_to_date: int = 0
    packages_with_errors: int = 0
    error_details: List[str] = field(default_factory=list)
    conda_forge_newer: int = 0
    upstream_newer: int = 0
    unsupported_sources: int = 0

    def add_error(self, package_name: str, error: str):
        """Add an error for a specific package."""
        self.packages_with_errors += 1
        self.error_details.append(f"{package_name}: {error}")

    def print_summary(self):
        """Print a comprehensive summary of the update process."""
        print("\n" + "="*80)
        print("🏁 UPDATE SUMMARY")
        print("="*80)

        print(f"📦 Total packages processed: {self.total_packages}")
        print()

        print("🌐 Conda-forge Status:")
        print(f"   ✅ Found on conda-forge: {self.packages_on_conda_forge}")
        print(f"   ❌ Not found on conda-forge: {self.packages_not_on_conda_forge}")
        if self.conda_forge_newer > 0:
            print(f"   🔼 Conda-forge has newer version: {self.conda_forge_newer}")
        print()

        print("🔄 Update Status:")
        print(f"   🆙 Packages updated: {self.packages_updated}")
        print(f"   ✅ Already up-to-date: {self.packages_up_to_date}")
        if self.upstream_newer > 0:
            print(f"   📈 Upstream has newer version: {self.upstream_newer}")
        print()

        if self.packages_with_errors > 0:
            print(f"❌ Packages with errors: {self.packages_with_errors}")
            if self.unsupported_sources > 0:
                print(f"   🚫 Unsupported source types: {self.unsupported_sources}")
            print("   Error details:")
            for error in self.error_details[:10]:  # Show first 10 errors
                print(f"     • {error}")
            if len(self.error_details) > 10:
                print(f"     ... and {len(self.error_details) - 10} more errors")
            print()

        # Success rate
        success_rate = ((self.packages_updated + self.packages_up_to_date) / self.total_packages * 100) if self.total_packages > 0 else 0
        print(f"📊 Success rate: {success_rate:.1f}% ({self.packages_updated + self.packages_up_to_date}/{self.total_packages})")

        if self.packages_updated > 0:
            print(f"\n🎉 {self.packages_updated} package(s) were successfully updated!")
        elif self.packages_up_to_date == self.total_packages:
            print(f"\n✅ All packages are already up-to-date!")

        print("="*80)


def get_cache_directory() -> Path:
    """Get or create a persistent cache directory for py-rattler data."""
    # Use project-local cache directory
    cache_dir = Path("./.cache/py-rattler")

    # Fallback to user home directory if project cache isn't writable
    if not cache_dir.parent.exists() or not os.access(cache_dir.parent, os.W_OK):
        home_cache = Path.home() / ".cache" / "meso-forge" / "py-rattler"
        cache_dir = home_cache

    # Create cache directory if it doesn't exist
    cache_dir.mkdir(parents=True, exist_ok=True)

    return cache_dir


def calculate_sha256(url: str) -> Optional[str]:
    """Download file and calculate SHA256."""
    try:
        response = requests.get(url, stream=True, timeout=30)
        if response.status_code == 200:
            sha256_hash = hashlib.sha256()
            for chunk in response.iter_content(chunk_size=8192):
                sha256_hash.update(chunk)
            return sha256_hash.hexdigest()
        else:
            print(f"HTTP {response.status_code} when downloading {url}")
    except requests.exceptions.Timeout:
        print(f"Timeout downloading {url}")
    except requests.exceptions.ConnectionError:
        print(f"Connection error downloading {url}")
    except Exception as e:
        print(f"Error calculating SHA256 for {url}: {e}")
    return None


def replace_version_string(content: str, new_version: str) -> str:
    """Replace first occurrence of version in content, line by line."""
    lines = content.splitlines()
    for i, line in enumerate(lines):
        if line.strip().startswith('version:'):
            # Keep the leading whitespace
            whitespace = line[:line.index('version:')]
            lines[i] = f'{whitespace}version: "{new_version}"'
            break
    return '\n'.join(lines)


async def get_conda_forge_versions(package_name: str) -> List[str]:
    """Get all available versions for a package from conda-forge."""
    try:
        channel = Channel("conda-forge")
        platforms = [Platform.current(), Platform("noarch")]

        # Use persistent cache directory
        cache_dir = get_cache_directory()

        def download_callback(downloaded: int, total: int):
            """Simple callback for download progress."""
            pass  # Silent callback - could add progress reporting here

        # Fetch repository data for conda-forge
        repo_data = await fetch_repo_data(
            channels=[channel],
            platforms=platforms,
            cache_path=cache_dir,
            callback=download_callback,
        )

        versions = []
        # repo_data is a list of SparseRepoData objects, one per platform
        for platform_data in repo_data:
            # Load all records from this platform
            records = platform_data.load_all_records()
            for record in records:
                if record.name == package_name:
                    # Convert version to string - it might be a VersionWithSource object
                    version_str = str(record.version)
                    versions.append(version_str)

        # Sort versions using semver if possible, otherwise lexicographically
        try:
            versions.sort(key=lambda v: semver.VersionInfo.parse(str(v).lstrip('v')), reverse=True)
        except:
            # Fallback to simple sorting if semver parsing fails
            versions.sort(key=str, reverse=True)

        return list(set(versions))  # Remove duplicates while preserving order
    except Exception as e:
        print(f"Error fetching conda-forge versions for {package_name}: {e}")
        return []


def get_github_latest_release(owner: str, repo: str, package_name: str, quiet: bool = False) -> Optional[str]:
    """Get latest release version from GitHub."""
    api_url = f"https://api.github.com/repos/{owner}/{repo}/releases/latest"

    # Use GitHub token if available
    token = os.getenv('GITHUB_TOKEN')
    headers = {}
    if token:
        headers['Authorization'] = f'token {token}'

    try:
        response = requests.get(api_url, headers=headers, timeout=30)
        if response.status_code == 200:
            resp_json = response.json()
            tag_name = resp_json.get('tag_name', '')

            if not tag_name:
                if not quiet:
                    print(f"({package_name}) No tag_name in GitHub response")
                return None

            # Clean up tag name
            if tag_name.startswith(package_name):
                tag_name = tag_name[len(package_name)+1:]
            if tag_name.startswith('v'):
                tag_name = tag_name[1:]

            return tag_name
        elif response.status_code == 404:
            if not quiet:
                print(f"({package_name}) No releases found for {owner}/{repo}")
        else:
            if not quiet:
                print(f"({package_name}) Could not fetch releases: {response.status_code}")
    except requests.exceptions.Timeout:
        if not quiet:
            print(f"({package_name}) Timeout fetching GitHub release")
    except requests.exceptions.ConnectionError:
        if not quiet:
            print(f"({package_name}) Connection error fetching GitHub release")
    except Exception as e:
        if not quiet:
            print(f"({package_name}) Error fetching GitHub release: {e}")

    return None


def get_github_latest_tag(owner: str, repo: str, package_name: str, quiet: bool = False) -> Optional[str]:
    """Get latest tagged version from GitHub."""
    api_url = f"https://api.github.com/repos/{owner}/{repo}/tags"

    token = os.getenv('GITHUB_TOKEN')
    headers = {}
    if token:
        headers['Authorization'] = f'token {token}'

    try:
        response = requests.get(api_url, headers=headers, timeout=30)
        if response.status_code == 200:
            latest_version = None
            resp_json = response.json()

            if not isinstance(resp_json, list):
                if not quiet:
                    print(f"({package_name}) Unexpected GitHub tags response format")
                return None

            for tag in resp_json:
                if not isinstance(tag, dict) or 'name' not in tag:
                    continue

                candidate = tag['name']

                # Clean up tag name
                if candidate.startswith(package_name):
                    candidate = candidate[len(package_name)+1:]
                if candidate.startswith('v'):
                    candidate = candidate[1:]

                if latest_version is None:
                    latest_version = candidate
                else:
                    try:
                        if semver.compare(candidate, latest_version) > 0:
                            latest_version = candidate
                    except:
                        # Fallback to string comparison if semver fails
                        if candidate > latest_version:
                            latest_version = candidate

            return latest_version
        else:
            if not quiet:
                print(f"({package_name}) Could not fetch tags: {response.status_code}")
    except requests.exceptions.Timeout:
        if not quiet:
            print(f"({package_name}) Timeout fetching GitHub tags")
    except requests.exceptions.ConnectionError:
        if not quiet:
            print(f"({package_name}) Connection error fetching GitHub tags")
    except Exception as e:
        if not quiet:
            print(f"({package_name}) Error fetching GitHub tags: {e}")

    return None


async def check_package_on_conda_forge(package_name: str, current_version: str) -> Dict[str, Any]:
    """Check if package exists on conda-forge and what versions are available."""
    conda_versions = await get_conda_forge_versions(package_name)

    result = {
        'exists_on_conda_forge': len(conda_versions) > 0,
        'conda_forge_versions': conda_versions,
        'latest_conda_forge_version': conda_versions[0] if conda_versions else None,
        'current_version_on_conda_forge': current_version in conda_versions
    }

    return result


async def get_upstream_latest_version(source_url: str, package_name: str, quiet: bool = False) -> Optional[str]:
    """Get the latest version from upstream source."""
    if 'github.com' in source_url:
        # Extract owner/repo from GitHub URL
        try:
            parts = source_url.split('github.com/')[1].split('/')
            owner, repo = parts[0], parts[1]

            # Try releases first, then tags
            version = get_github_latest_release(owner, repo, package_name, quiet)
            if version is None:
                version = get_github_latest_tag(owner, repo, package_name, quiet)

            return version
        except Exception as e:
            if not quiet:
                print(f"({package_name}) Error parsing GitHub URL {source_url}: {e}")

    elif 'pypi.org' in source_url:
        print(f"({package_name}) PyPI support not yet implemented")
    elif 'registry.npmjs.org' in source_url:
        print(f"({package_name}) npm registry support not yet implemented")
    else:
        print(f"({package_name}) Unsupported source URL format: {source_url}")

    return None


async def update_recipe_source(recipe_path: Path, recipe: Dict[str, Any],
                              current_version: str, package_name: str,
                              source: Dict[str, Any], stats: UpdateStats,
                              dry_run: bool = False, quiet: bool = False) -> bool:
    """Update version and hash in recipe source."""
    if 'if' in source:
        source = source['then']

    if 'path' in source:
        if not quiet:
            print(f"({package_name}) Skipping local path source")
        return False

    if 'url' not in source and 'git' not in source:
        if not quiet:
            print(f"({package_name}) No supported source URL found")
        stats.unsupported_sources += 1
        return False

    # Check conda-forge first
    if not quiet:
        print(f"({package_name}) Checking conda-forge availability...")
    conda_info = await check_package_on_conda_forge(package_name, current_version)

    if conda_info['exists_on_conda_forge']:
        stats.packages_on_conda_forge += 1
        if not quiet:
            print(f"({package_name}) Package exists on conda-forge with {len(conda_info['conda_forge_versions'])} versions")
            print(f"({package_name}) Latest on conda-forge: {conda_info['latest_conda_forge_version']}")

            if conda_info['current_version_on_conda_forge']:
                print(f"({package_name}) Current version {current_version} is available on conda-forge")
            else:
                print(f"({package_name}) Current version {current_version} is NOT available on conda-forge")

        # Check if conda-forge has a newer version
        try:
            latest_conda = conda_info['latest_conda_forge_version']
            if latest_conda and semver.compare(latest_conda, current_version) > 0:
                stats.conda_forge_newer += 1
        except:
            pass
    else:
        stats.packages_not_on_conda_forge += 1
        if not quiet:
            print(f"({package_name}) Package not found on conda-forge")

    # Get upstream latest version
    source_url = source.get('url') or source.get('git', '')
    if not source_url:
        if not quiet:
            print(f"({package_name}) No source URL found")
        return False

    if not quiet:
        print(f"({package_name}) Checking upstream for latest version...")
    upstream_version = await get_upstream_latest_version(source_url, package_name, quiet)

    if not upstream_version:
        if not quiet:
            print(f"({package_name}) Could not determine upstream version")
        stats.add_error(package_name, "Could not determine upstream version")
        return False

    if not quiet:
        print(f"({package_name}) Current: {current_version}, Upstream: {upstream_version}")

    # Compare versions
    if current_version == upstream_version:
        if not quiet:
            print(f"({package_name}) Already at latest upstream version")
        stats.packages_up_to_date += 1
        return False

    try:
        if semver.compare(current_version, upstream_version) >= 0:
            if not quiet:
                print(f"({package_name}) Current version is newer than or equal to upstream")
            stats.packages_up_to_date += 1
            return False
    except:
        # Fallback to string comparison
        if current_version >= upstream_version:
            if not quiet:
                print(f"({package_name}) Current version appears to be up to date (string comparison)")
            stats.packages_up_to_date += 1
            return False

    # Mark that upstream has newer version
    stats.upstream_newer += 1

    if dry_run:
        if not quiet:
            print(f"({package_name}) [DRY RUN] Would update to version {upstream_version}")
        return True

    # Update recipe
    if 'url' in source:
        new_url = source_url.replace("${{ version }}", upstream_version).replace("{{ version }}", upstream_version)
        new_hash = calculate_sha256(new_url)

        if not new_hash:
            if not quiet:
                print(f"({package_name}) Failed to calculate new hash")
            stats.add_error(package_name, "Failed to calculate SHA256 hash")
            return False

        # Update the recipe file
        recipe_str = recipe_path.read_text()
        recipe_str = replace_version_string(recipe_str, upstream_version)
        recipe_str = recipe_str.replace(source['sha256'], new_hash)

        recipe_path.write_text(recipe_str.strip())
        if not quiet:
            print(f"({package_name}) Updated to version {upstream_version}")
        stats.packages_updated += 1
        return True

    elif 'git' in source:
        if not quiet:
            print(f"({package_name}) Git source updates not yet fully implemented")
        stats.add_error(package_name, "Git source updates not implemented")
        return False

    return False


async def update_recipe(recipe_path: Path, stats: UpdateStats, dry_run: bool = False, quiet: bool = False) -> None:
    """Update version and hash in recipe file."""
    try:
        if not recipe_path.exists():
            print(f"Recipe file {recipe_path} does not exist")
            return

        with open(recipe_path, 'r', encoding='utf-8') as f:
            recipe = yaml.safe_load(f)

        if not recipe:
            print(f"Empty or invalid YAML in {recipe_path}")
            return

        if 'context' not in recipe:
            print(f"No 'context' section in {recipe_path}")
            return

        if 'version' not in recipe['context']:
            print(f"No 'version' in context section of {recipe_path}")
            return

        if 'package' not in recipe or 'name' not in recipe['package']:
            print(f"No package name found in {recipe_path}")
            return

        if 'source' not in recipe:
            print(f"No 'source' section in {recipe_path}")
            return

        current_version = recipe['context']['version']
        package_name = recipe['package']['name']

        stats.total_packages += 1

        if not quiet:
            print(f"\n{'='*60}")
            print(f"Processing {package_name} (current version: {current_version})")
            print(f"{'='*60}")

        sources = recipe['source']

        if isinstance(sources, dict):
            await update_recipe_source(recipe_path, recipe, current_version, package_name, sources, stats, dry_run, quiet)
        elif isinstance(sources, list):
            for source in sources:
                if isinstance(source, dict):
                    await update_recipe_source(recipe_path, recipe, current_version, package_name, source, stats, dry_run, quiet)
                else:
                    if not quiet:
                        print(f"({package_name}) Non-dict source item: {type(source)}")
                    stats.add_error(package_name, f"Non-dict source item: {type(source)}")
        else:
            if not quiet:
                print(f"({package_name}) Unsupported source format: {type(sources)}")
            stats.add_error(package_name, f"Unsupported source format: {type(sources)}")

    except yaml.YAMLError as e:
        print(f"YAML parsing error in {recipe_path}: {e}")
        stats.add_error(recipe_path.name, f"YAML parsing error: {e}")
    except FileNotFoundError:
        print(f"Recipe file not found: {recipe_path}")
        stats.add_error(recipe_path.name, "Recipe file not found")
    except PermissionError:
        print(f"Permission denied reading {recipe_path}")
        stats.add_error(recipe_path.name, "Permission denied")
    except Exception as e:
        print(f"Error processing {recipe_path}: {e}")
        stats.add_error(recipe_path.name, f"Unexpected error: {e}")


def find_recipe_files(recipes_dir: Path, package_names: Optional[List[str]] = None) -> List[Path]:
    """Find recipe files based on criteria."""
    if not recipes_dir.exists():
        print(f"❌ Recipe directory {recipes_dir} does not exist")
        sys.exit(1)

    if package_names:
        # Find specific packages
        recipe_files = []
        for package_name in package_names:
            recipe_path = recipes_dir / package_name / "recipe.yaml"
            if recipe_path.exists():
                recipe_files.append(recipe_path)
            else:
                print(f"❌ Recipe not found for package: {package_name}")
                print(f"   Expected: {recipe_path}")
        return recipe_files
    else:
        # Find all recipe files
        return list(recipes_dir.glob('**/recipe.yaml'))


def list_available_packages(recipes_dir: Path) -> None:
    """List all available packages."""
    recipe_files = list(recipes_dir.glob('**/recipe.yaml'))

    if not recipe_files:
        print(f"No recipe files found in {recipes_dir}")
        return

    print(f"📦 Available packages in {recipes_dir}:")
    print("=" * 50)

    packages = []
    for recipe_file in sorted(recipe_files):
        package_name = recipe_file.parent.name
        packages.append(package_name)

    # Print in columns
    packages.sort()
    for i, package in enumerate(packages):
        if i % 3 == 0 and i > 0:
            print()
        print(f"  {package:<20}", end="")

    print(f"\n\nTotal: {len(packages)} packages")


async def check_conda_forge_status_only(recipe_files: List[Path], quiet: bool = False) -> None:
    """Check only conda-forge status for packages."""
    if not quiet:
        print("🌐 Checking conda-forge status only...")
        print("=" * 60)

    stats = UpdateStats()

    for recipe_file in recipe_files:
        try:
            with open(recipe_file, 'r') as f:
                recipe = yaml.safe_load(f)

            if not recipe or 'package' not in recipe or 'context' not in recipe:
                continue

            package_name = recipe['package']['name']
            current_version = recipe['context']['version']
            stats.total_packages += 1

            if not quiet:
                print(f"\n📦 {package_name} (v{current_version})")

            conda_info = await check_package_on_conda_forge(package_name, current_version)

            if conda_info['exists_on_conda_forge']:
                stats.packages_on_conda_forge += 1
                latest_conda = conda_info['latest_conda_forge_version']
                version_count = len(conda_info['conda_forge_versions'])

                if not quiet:
                    print(f"   ✅ Found on conda-forge: {version_count} version(s)")
                    print(f"   📌 Latest: {latest_conda}")

                    if conda_info['current_version_on_conda_forge']:
                        print(f"   🎯 Current version available: Yes")
                    else:
                        print(f"   🎯 Current version available: No")
                else:
                    status = "✅" if conda_info['current_version_on_conda_forge'] else "⚠️"
                    print(f"{status} {package_name}: {latest_conda} (conda-forge)")
            else:
                stats.packages_not_on_conda_forge += 1
                if not quiet:
                    print(f"   ❌ Not found on conda-forge")
                else:
                    print(f"❌ {package_name}: Not on conda-forge")

        except Exception as e:
            if not quiet:
                print(f"❌ Error checking {recipe_file}: {e}")
            stats.add_error(recipe_file.name, str(e))

    if not quiet:
        print("\n" + "=" * 60)
        print(f"📊 Conda-forge Summary:")
        print(f"   Found: {stats.packages_on_conda_forge}/{stats.total_packages}")
        print(f"   Not found: {stats.packages_not_on_conda_forge}/{stats.total_packages}")


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Version control for meso-forge packages using py-rattler",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --all                        # Check all packages
  %(prog)s --package fd                 # Check specific package
  %(prog)s --package fd --package pwgen # Check multiple packages
  %(prog)s --conda-forge-only           # Only check conda-forge status
  %(prog)s --dry-run --all              # Show what would be updated
  %(prog)s --update --all               # Update all packages
  %(prog)s --newer-only                 # Only show packages with newer versions
  %(prog)s --list-packages              # List all available packages
        """
    )

    # Package selection
    package_group = parser.add_mutually_exclusive_group()
    package_group.add_argument(
        '--all', '-a',
        action='store_true',
        help='Check all packages in the recipes directory'
    )
    package_group.add_argument(
        '--package', '-p',
        action='append',
        metavar='NAME',
        help='Check specific package(s) (can be used multiple times)'
    )
    package_group.add_argument(
        '--list-packages', '-l',
        action='store_true',
        help='List all available packages and exit'
    )

    # Operation modes
    parser.add_argument(
        '--update', '-u',
        action='store_true',
        help='Actually update recipe files (default is check-only mode)'
    )
    parser.add_argument(
        '--dry-run', '-n',
        action='store_true',
        help='Show what would be updated without making changes'
    )
    parser.add_argument(
        '--conda-forge-only', '-c',
        action='store_true',
        help='Only check conda-forge status, skip upstream checks'
    )
    parser.add_argument(
        '--newer-only',
        action='store_true',
        help='Only show packages where newer versions are available'
    )

    # Directories and paths
    parser.add_argument(
        '--recipes-dir', '-d',
        type=Path,
        default=Path('./pkgs'),
        help='Directory containing recipe files (default: ./pkgs)'
    )

    # Output options
    parser.add_argument(
        '--quiet', '-q',
        action='store_true',
        help='Reduce output verbosity'
    )
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Increase output verbosity'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    return parser.parse_args()


async def main():
    """Main entry point."""
    args = parse_arguments()

    # Handle list packages
    if args.list_packages:
        list_available_packages(args.recipes_dir)
        return

    # Determine which packages to check
    if args.all:
        recipe_files = find_recipe_files(args.recipes_dir)
    elif args.package:
        recipe_files = find_recipe_files(args.recipes_dir, args.package)
    else:
        print("❌ Must specify --all, --package NAME, or --list-packages")
        sys.exit(1)

    if not recipe_files:
        print("❌ No recipe files found to process")
        sys.exit(1)

    if not args.quiet and not args.json:
        print(f"🔍 Found {len(recipe_files)} recipe file(s) to process")

    # Handle conda-forge only mode
    if args.conda_forge_only:
        await check_conda_forge_status_only(recipe_files, args.quiet or args.json)
        return

    # Determine operation mode
    if args.dry_run:
        if not args.quiet and not args.json:
            print("🧪 DRY RUN MODE - No files will be modified")
            print("=" * 60)
        update_mode = False
        dry_run = True
    elif args.update:
        if not args.quiet and not args.json:
            print("🔄 UPDATE MODE - Files will be modified")
            print("=" * 60)
        update_mode = True
        dry_run = False
    else:
        if not args.quiet and not args.json:
            print("👁️  CHECK MODE - No files will be modified (use --update to modify files)")
            print("=" * 60)
        update_mode = False
        dry_run = True

    # Process packages with full update logic
    stats = UpdateStats()

    for recipe_file in recipe_files:
        await update_recipe(recipe_file, stats, dry_run, args.quiet or args.json)

    # Print results
    if not args.quiet and not args.json:
        stats.print_summary()

    # Handle JSON output
    if args.json:
        import json
        results = {
            "total_packages": stats.total_packages,
            "packages_on_conda_forge": stats.packages_on_conda_forge,
            "packages_not_on_conda_forge": stats.packages_not_on_conda_forge,
            "packages_updated": stats.packages_updated,
            "packages_up_to_date": stats.packages_up_to_date,
            "packages_with_errors": stats.packages_with_errors,
            "conda_forge_newer": stats.conda_forge_newer,
            "upstream_newer": stats.upstream_newer,
            "unsupported_sources": stats.unsupported_sources,
            "error_details": stats.error_details
        }
        print(json.dumps(results, indent=2))
        return

    # Handle newer-only mode
    if args.newer_only and stats.upstream_newer == 0:
        if not args.quiet and not args.json:
            print("✅ All packages are up-to-date!")

    # Set exit code based on results
    if stats.packages_with_errors > 0:
        sys.exit(1)


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n❌ Interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        sys.exit(1)
