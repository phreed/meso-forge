#!/usr/bin/env python3
"""
Version control for meso-forge packages using APIs to get full URLs.

This script uses exact URLs from APIs (GitHub, RubyGems, etc.) instead of
template substitution whenever possible, making updates more reliable.
"""

import argparse
import asyncio
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union, Any, NamedTuple
import requests
try:
    from ruamel.yaml import YAML
    from ruamel.yaml.error import YAMLError
    HAS_RUAMEL_YAML = True
except ImportError:
    import yaml
    from yaml import YAMLError
    HAS_RUAMEL_YAML = False
import semver


class VersionInfo(NamedTuple):
    """Container for version information from APIs."""
    version: str
    download_url: Optional[str] = None
    tag_name: Optional[str] = None
    source_type: str = "unknown"  # github, rubygems, pypi, npm, etc.


class UpdateStats:
    """Statistics for update operations."""

    def __init__(self):
        self.total_packages = 0
        self.packages_updated = 0
        self.packages_up_to_date = 0
        self.packages_on_conda_forge = 0
        self.packages_not_on_conda_forge = 0
        self.conda_forge_newer = 0
        self.upstream_newer = 0
        self.unsupported_sources = 0
        self.errors: List[Tuple[str, str]] = []

    def add_error(self, package_name: str, error_message: str):
        """Add an error for a package."""
        self.errors.append((package_name, error_message))

    def print_summary(self):
        """Print a formatted summary of the update statistics."""
        print("\n" + "="*80)
        print("🏁 UPDATE SUMMARY")
        print("="*80)
        print(f"📦 Total packages processed: {self.total_packages}")

        if self.total_packages > 0:
            print(f"\n🌐 Conda-forge Status:")
            print(f"   ✅ Found on conda-forge: {self.packages_on_conda_forge}")
            print(f"   ❌ Not found on conda-forge: {self.packages_not_on_conda_forge}")

            if self.conda_forge_newer > 0:
                print(f"   📈 Conda-forge has newer versions: {self.conda_forge_newer}")

            print(f"\n🔄 Update Status:")
            print(f"   🆙 Packages updated: {self.packages_updated}")
            print(f"   ✅ Already up-to-date: {self.packages_up_to_date}")
            if self.upstream_newer > 0:
                print(f"   📈 Upstream has newer version: {self.upstream_newer}")

            if self.unsupported_sources > 0:
                print(f"   ⚠️  Unsupported sources: {self.unsupported_sources}")

            if self.errors:
                print(f"\n❌ Packages with errors: {len(self.errors)}")
                print(f"   Error details:")
                for pkg, error in self.errors:
                    print(f"     • {pkg}: {error}")

            success_rate = (self.packages_updated + self.packages_up_to_date) / self.total_packages * 100
            print(f"\n📊 Success rate: {success_rate:.1f}% ({self.packages_updated + self.packages_up_to_date}/{self.total_packages})")

            if self.packages_updated == 0 and len(self.errors) == 0 and self.packages_up_to_date > 0:
                print("\n✅ All packages are already up-to-date!")

        print("="*80)


def get_cache_directory() -> Path:
    """Get cache directory for temporary files."""
    cache_dir = Path.home() / ".cache" / "meso-forge-version-ctl"
    cache_dir.mkdir(parents=True, exist_ok=True)
    return cache_dir


def calculate_sha256(url: str) -> Optional[str]:
    """Calculate SHA256 hash of a file from URL."""
    try:
        response = requests.get(url, stream=True, timeout=30)
        if response.status_code == 200:
            sha256_hash = hashlib.sha256()
            for chunk in response.iter_content(chunk_size=8192):
                sha256_hash.update(chunk)
            return sha256_hash.hexdigest()
        else:
            print(f"HTTP {response.status_code} when downloading {url}")
            return None
    except Exception as e:
        print(f"Error downloading {url}: {e}")
        return None


def update_yaml_version(recipe_data: dict, new_version: str) -> None:
    """Update version in recipe YAML data structure."""
    if 'context' in recipe_data and 'version' in recipe_data['context']:
        recipe_data['context']['version'] = new_version


async def get_conda_forge_versions(package_name: str, quiet: bool = False) -> Dict[str, Any]:
    """Get conda-forge package information."""
    url = f"https://api.anaconda.org/package/conda-forge/{package_name}"

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(url, timeout=30) as response:
                if response.status == 200:
                    data = await response.json()
                    versions = [file['version'] for file in data.get('files', [])]
                    unique_versions = sorted(set(versions), key=lambda x: x, reverse=True)
                    return {
                        'exists': True,
                        'versions': unique_versions,
                        'latest': unique_versions[0] if unique_versions else None
                    }
                else:
                    return {'exists': False, 'versions': [], 'latest': None}
    except Exception as e:
        if not quiet:
            print(f"({package_name}) Error checking conda-forge: {e}")
        return {'exists': False, 'versions': [], 'latest': None}


def get_github_latest_release(owner: str, repo: str, package_name: str,
                            version_patterns: Optional[List[str]] = None,
                            quiet: bool = False) -> Optional[VersionInfo]:
    """Get latest release version and download URL from GitHub using releases API."""
    api_url = f"https://api.github.com/repos/{owner}/{repo}/releases"

    # Default version pattern if none provided
    if not version_patterns:
        version_patterns = [r'^(\d+\.\d+\.\d+)']

    # Use GitHub token if available
    token = os.getenv('GITHUB_TOKEN')
    headers = {}
    if token:
        headers['Authorization'] = f'token {token}'

    try:
        response = requests.get(api_url, headers=headers, timeout=30)
        if response.status_code == 200:
            releases = response.json()

            if not releases:
                if not quiet:
                    print(f"({package_name}) No releases found for {owner}/{repo}")
                return None

            valid_releases = []

            for release in releases:
                # Skip drafts and pre-releases
                if release.get('draft', False) or release.get('prerelease', False):
                    continue

                tag_name = release.get('tag_name', '')
                if not tag_name:
                    continue

                # Clean up tag name for version extraction
                cleaned_tag = tag_name
                if cleaned_tag.startswith(package_name):
                    cleaned_tag = cleaned_tag[len(package_name)+1:]
                if cleaned_tag.startswith('v'):
                    cleaned_tag = cleaned_tag[1:]

                # Check if version matches any of the patterns
                for pattern in version_patterns:
                    try:
                        match = re.match(pattern, cleaned_tag)
                        if match:
                            # Extract the version (first capture group or full match)
                            version = match.group(1) if match.groups() else match.group(0)

                            # Get the tarball download URL from the release
                            tarball_url = release.get('tarball_url')
                            if not tarball_url:
                                # Fallback to constructed URL
                                tarball_url = f"https://github.com/{owner}/{repo}/archive/refs/tags/{tag_name}.tar.gz"

                            valid_releases.append(VersionInfo(
                                version=version,
                                download_url=tarball_url,
                                tag_name=tag_name,
                                source_type="github"
                            ))
                            break
                    except re.error as e:
                        if not quiet:
                            print(f"({package_name}) Invalid regex pattern '{pattern}': {e}")
                        continue

            if not valid_releases:
                if not quiet:
                    print(f"({package_name}) No releases match version patterns: {version_patterns}")
                return None

            # Sort versions and return the latest
            try:
                # Sort by semantic version
                valid_releases.sort(key=lambda x: semver.VersionInfo.parse(x.version), reverse=True)
                latest = valid_releases[0]
                if not quiet:
                    print(f"({package_name}) Found {len(valid_releases)} matching releases, latest: {latest.version}")
                    print(f"({package_name}) Download URL: {latest.download_url}")
                return latest
            except (ValueError, TypeError) as e:
                if not quiet:
                    print(f"({package_name}) Error parsing semantic versions, using string sort: {e}")
                # Fallback to string sort
                valid_releases.sort(key=lambda x: x.version, reverse=True)
                return valid_releases[0]

        elif response.status_code == 404:
            if not quiet:
                print(f"({package_name}) No releases found for {owner}/{repo}")
        else:
            if not quiet:
                print(f"({package_name}) Could not fetch releases: {response.status_code}")
    except requests.exceptions.Timeout:
        if not quiet:
            print(f"({package_name}) Timeout fetching GitHub releases")
    except requests.exceptions.ConnectionError:
        if not quiet:
            print(f"({package_name}) Connection error fetching GitHub releases")
    except Exception as e:
        if not quiet:
            print(f"({package_name}) Error fetching GitHub releases: {e}")

    return None


def get_github_latest_tag(owner: str, repo: str, package_name: str,
                         version_patterns: Optional[List[str]] = None,
                         quiet: bool = False) -> Optional[VersionInfo]:
    """Get latest tag version and download URL from GitHub using tags API."""
    api_url = f"https://api.github.com/repos/{owner}/{repo}/tags"

    # Default version pattern if none provided
    if not version_patterns:
        version_patterns = [r'^(\d+\.\d+\.\d+)']

    # Use GitHub token if available
    token = os.getenv('GITHUB_TOKEN')
    headers = {}
    if token:
        headers['Authorization'] = f'token {token}'

    try:
        response = requests.get(api_url, headers=headers, timeout=30)
        if response.status_code == 200:
            tags = response.json()

            if not tags:
                if not quiet:
                    print(f"({package_name}) No tags found for {owner}/{repo}")
                return None

            valid_tags = []

            for tag in tags:
                tag_name = tag.get('name', '')
                if not tag_name:
                    continue

                # Clean up tag name for version extraction
                cleaned_tag = tag_name
                if cleaned_tag.startswith(package_name):
                    cleaned_tag = cleaned_tag[len(package_name)+1:]
                if cleaned_tag.startswith('v'):
                    cleaned_tag = cleaned_tag[1:]

                # Check if version matches any of the patterns
                for pattern in version_patterns:
                    try:
                        match = re.match(pattern, cleaned_tag)
                        if match:
                            # Extract the version (first capture group or full match)
                            version = match.group(1) if match.groups() else match.group(0)

                            # Get the tarball download URL from the tag
                            tarball_url = tag.get('tarball_url')
                            if not tarball_url:
                                # Fallback to constructed URL
                                tarball_url = f"https://github.com/{owner}/{repo}/archive/refs/tags/{tag_name}.tar.gz"

                            valid_tags.append(VersionInfo(
                                version=version,
                                download_url=tarball_url,
                                tag_name=tag_name,
                                source_type="github"
                            ))
                            break
                    except re.error as e:
                        if not quiet:
                            print(f"({package_name}) Invalid regex pattern '{pattern}': {e}")
                        continue

            if not valid_tags:
                if not quiet:
                    print(f"({package_name}) No tags match version patterns: {version_patterns}")
                return None

            # Sort versions and return the latest
            try:
                # Sort by semantic version
                valid_tags.sort(key=lambda x: semver.VersionInfo.parse(x.version), reverse=True)
                latest = valid_tags[0]
                if not quiet:
                    print(f"({package_name}) Found {len(valid_tags)} matching tags, latest: {latest.version}")
                    print(f"({package_name}) Download URL: {latest.download_url}")
                return latest
            except (ValueError, TypeError) as e:
                if not quiet:
                    print(f"({package_name}) Error parsing semantic versions, using string sort: {e}")
                # Fallback to string sort
                valid_tags.sort(key=lambda x: x.version, reverse=True)
                return valid_tags[0]

        elif response.status_code == 404:
            if not quiet:
                print(f"({package_name}) No tags found for {owner}/{repo}")
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


def get_rubygems_latest_release(gem_name: str, package_name: str,
                               version_patterns: Optional[List[str]] = None,
                               quiet: bool = False) -> Optional[VersionInfo]:
    """Get latest gem version and download URL from RubyGems API."""
    api_url = f"https://rubygems.org/api/v1/gems/{gem_name}.json"

    # Default version pattern if none provided
    if not version_patterns:
        version_patterns = [r'^(\d+\.\d+\.\d+)']

    try:
        response = requests.get(api_url, timeout=30)
        if response.status_code == 200:
            gem_info = response.json()
            latest_version = gem_info.get('version')

            if not latest_version:
                if not quiet:
                    print(f"({package_name}) No version found for gem {gem_name}")
                return None

            # Check if version matches any of the patterns
            for pattern in version_patterns:
                try:
                    match = re.match(pattern, latest_version)
                    if match:
                        # Extract the version (first capture group or full match)
                        version = match.group(1) if match.groups() else match.group(0)

                        # Construct download URL for the gem
                        download_url = f"https://rubygems.org/downloads/{gem_name}-{latest_version}.gem"

                        if not quiet:
                            print(f"({package_name}) Found gem version: {version}")
                            print(f"({package_name}) Download URL: {download_url}")

                        return VersionInfo(
                            version=version,
                            download_url=download_url,
                            tag_name=latest_version,
                            source_type="rubygems"
                        )
                except re.error as e:
                    if not quiet:
                        print(f"({package_name}) Invalid regex pattern '{pattern}': {e}")
                    continue

            if not quiet:
                print(f"({package_name}) Gem version {latest_version} doesn't match patterns: {version_patterns}")

        elif response.status_code == 404:
            if not quiet:
                print(f"({package_name}) Gem {gem_name} not found on RubyGems")
        else:
            if not quiet:
                print(f"({package_name}) Could not fetch gem info: {response.status_code}")
    except Exception as e:
        if not quiet:
            print(f"({package_name}) Error fetching RubyGems info: {e}")

    return None


async def check_package_on_conda_forge(package_name: str, current_version: str) -> Dict[str, Any]:
    """Check if package exists on conda-forge and get version info."""
    conda_info = await get_conda_forge_versions(package_name, quiet=True)

    result = {
        'exists_on_conda_forge': conda_info['exists'],
        'conda_forge_versions': conda_info['versions'],
        'latest_conda_forge_version': conda_info['latest'],
        'current_version_on_conda_forge': current_version in conda_info['versions']
    }

    return result


async def get_upstream_latest_version(source_url: str, package_name: str,
                                    version_patterns: Optional[List[str]] = None,
                                    mode: Optional[str] = None,
                                    mode_explicit: bool = False,
                                    quiet: bool = False) -> Optional[VersionInfo]:
    """Get the latest version info from upstream source including download URL."""
    # Determine the mode from URL if not explicitly provided
    if mode is None:
        if 'github.com' in source_url:
            mode = 'github'
        elif 'rubygems.org' in source_url:
            mode = 'rubygems'
        elif 'pypi.org' in source_url:
            mode = 'pypi'
        elif 'registry.npmjs.org' in source_url:
            mode = 'npm'
        else:
            if not quiet:
                print(f"({package_name}) Unable to determine mode from URL: {source_url}")
            return None

    if mode == 'github' or mode == 'github-release' or mode == 'github-tags':
        if 'github.com' not in source_url:
            if not quiet:
                print(f"({package_name}) GitHub mode specified but URL is not GitHub: {source_url}")
            return None

        # Extract owner/repo from GitHub URL
        try:
            parts = source_url.split('github.com/')[1].split('/')
            owner, repo = parts[0], parts[1]

            if mode == 'github-tags':
                # Use tags API specifically
                version_info = get_github_latest_tag(owner, repo, package_name, version_patterns, quiet)
            elif mode == 'github-release':
                # Use releases API specifically
                version_info = get_github_latest_release(owner, repo, package_name, version_patterns, quiet)
            else:
                # Auto-detected github mode - try releases first, then tags as fallback
                version_info = get_github_latest_release(owner, repo, package_name, version_patterns, quiet)
                if version_info is None and not mode_explicit:
                    if not quiet:
                        print(f"({package_name}) No matching releases found, trying tags...")
                    version_info = get_github_latest_tag(owner, repo, package_name, version_patterns, quiet)

            return version_info
        except Exception as e:
            if not quiet:
                print(f"({package_name}) Error parsing GitHub URL {source_url}: {e}")

    elif mode == 'rubygems':
        # Extract gem name from URL or use package name
        gem_name = package_name
        if 'rubygems.org' in source_url:
            try:
                # Try to extract gem name from URL like https://rubygems.org/gems/gem-name
                if '/gems/' in source_url:
                    gem_name = source_url.split('/gems/')[1].split('/')[0]
                    if not quiet:
                        print(f"({package_name}) Extracted gem name from URL: {gem_name}")
            except Exception as e:
                if not quiet:
                    print(f"({package_name}) Using package name as gem name due to URL parsing error: {e}")

        return get_rubygems_latest_release(gem_name, package_name, version_patterns, quiet)

    elif mode == 'pypi':
        if not quiet:
            print(f"({package_name}) PyPI support not yet implemented")
    elif mode == 'npm':
        if not quiet:
            print(f"({package_name}) npm registry support not yet implemented")
    else:
        if not quiet:
            print(f"({package_name}) Unsupported mode: {mode}")

    return None


async def update_recipe_source(recipe_path: Path, recipe: Dict[str, Any],
                              current_version: str, package_name: str,
                              source: Dict[str, Any], stats: UpdateStats,
                              dry_run: bool = False, quiet: bool = False) -> bool:
    """Update version and hash in recipe source using API URLs when available."""
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

    # Get upstream latest version info (including download URL)
    source_url = source.get('url') or source.get('git', '')
    if not source_url:
        if not quiet:
            print(f"({package_name}) No source URL found")
        return False

    # Extract version patterns and mode from recipe extra section
    version_patterns = None
    mode = None
    mode_explicit = False
    if 'extra' in recipe:
        # New structured format: extra.version.{mode}: [patterns]
        if 'version' in recipe['extra']:
            version_config = recipe['extra']['version']
            if isinstance(version_config, dict):
                for mode_key, patterns in version_config.items():
                    if patterns:  # Use the first non-empty mode found
                        # Map structured mode names to internal API mode names
                        mode_mapping = {
                            'github-release': 'github-release',
                            'github-tags': 'github-tags',
                            'rubygems-api': 'rubygems',
                            'pypi-api': 'pypi',
                            'npm-api': 'npm'
                        }
                        mode = mode_mapping.get(mode_key, mode_key)
                        version_patterns = patterns if isinstance(patterns, list) else [patterns]
                        mode_explicit = True
                        break
                if not quiet and mode:
                    print(f"({package_name}) Using mode: {mode}")
                    print(f"({package_name}) Using version patterns: {version_patterns}")

        # Backward compatibility with old syntax
        elif 'version-pattern' in recipe['extra']:
            version_patterns = recipe['extra']['version-pattern']
            if not quiet:
                print(f"({package_name}) Using version patterns: {version_patterns}")
            if 'mode' in recipe['extra']:
                mode = recipe['extra']['mode']
                mode_explicit = True
                if not quiet:
                    print(f"({package_name}) Using mode: {mode}")

    if not quiet:
        print(f"({package_name}) Checking upstream for latest version...")
    upstream_info = await get_upstream_latest_version(source_url, package_name, version_patterns, mode, mode_explicit, quiet)

    if not upstream_info:
        if not quiet:
            print(f"({package_name}) Could not determine upstream version")
        stats.add_error(package_name, "Could not determine upstream version")
        return False

    upstream_version = upstream_info.version

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
            if upstream_info.download_url:
                print(f"({package_name}) [DRY RUN] Would use API URL: {upstream_info.download_url}")
            else:
                print(f"({package_name}) [DRY RUN] Would use template substitution")
        return True

    # Update recipe
    if 'url' in source:
        # Use API-provided URL if available, otherwise fall back to template substitution
        if upstream_info.download_url:
            new_url = upstream_info.download_url
            if not quiet:
                print(f"({package_name}) Using API-provided URL: {new_url}")
        else:
            new_url = source_url.replace("${{ version }}", upstream_version).replace("{{ version }}", upstream_version)
            if not quiet:
                print(f"({package_name}) Using template substitution: {new_url}")

        new_hash = calculate_sha256(new_url)

        if not new_hash:
            if not quiet:
                print(f"({package_name}) Failed to calculate new hash")
            stats.add_error(package_name, "Failed to calculate SHA256 hash")
            return False

        # Update the recipe YAML object
        update_yaml_version(recipe, upstream_version)

        # Update URL if using API-provided URL, but preserve templates when possible
        if upstream_info.download_url and isinstance(source, dict):
            current_url = source['url']
            # Check if current URL is a template
            if '${{ version }}' in current_url or '{{ version }}' in current_url:
                # Expand the template with the new version
                expanded_template = current_url.replace("${{ version }}", upstream_version).replace("{{ version }}", upstream_version)
                # If template expansion matches API URL, keep the template
                if expanded_template == upstream_info.download_url:
                    if not quiet:
                        print(f"({package_name}) Template URL produces same result as API URL, preserving template")
                    # Don't update the URL, keep the template
                else:
                    if not quiet:
                        print(f"({package_name}) Template URL differs from API URL, using API URL")
                    source['url'] = new_url
            else:
                # Not a template, use API URL
                source['url'] = new_url

        # Update SHA256
        if isinstance(source, dict):
            source['sha256'] = new_hash

        # Write the updated YAML back to file
        if HAS_RUAMEL_YAML:
            yaml_processor = YAML()
            yaml_processor.preserve_quotes = True
            yaml_processor.width = 4096
            with open(recipe_path, 'w', encoding='utf-8') as f:
                yaml_processor.dump(recipe, f)
        else:
            with open(recipe_path, 'w', encoding='utf-8') as f:
                yaml.dump(recipe, f, default_flow_style=False, allow_unicode=True)
        if not quiet:
            print(f"({package_name}) Updated to version {upstream_version}")
            print(f"({package_name}) Updated URL to: {new_url}")
            print(f"({package_name}) Updated SHA256 to: {new_hash}")
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

        if HAS_RUAMEL_YAML:
            yaml_processor = YAML()
            yaml_processor.preserve_quotes = True
            yaml_processor.width = 4096
            with open(recipe_path, 'r', encoding='utf-8') as f:
                recipe = yaml_processor.load(f)
        else:
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
            if not sources:
                if not quiet:
                    print(f"({package_name}) Empty sources list")
                return

            # Only process the first source for version checking
            first_source = sources[0]
            if isinstance(first_source, dict):
                if len(sources) > 1 and not quiet:
                    print(f"({package_name}) Multiple sources found, only checking version for first source")
                await update_recipe_source(recipe_path, recipe, current_version, package_name, first_source, stats, dry_run, quiet)
            else:
                if not quiet:
                    print(f"({package_name}) First source is not a dict: {type(first_source)}")
                stats.add_error(package_name, f"First source is not a dict: {type(first_source)}")
        else:
            if not quiet:
                print(f"({package_name}) Unsupported source format: {type(sources)}")
            stats.add_error(package_name, f"Unsupported source format: {type(sources)}")

    except YAMLError as e:
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


def find_recipe_files(recipes_dir: Path) -> List[Path]:
    """Find all recipe.yaml files in the recipes directory."""
    recipe_files = []
    if recipes_dir.exists() and recipes_dir.is_dir():
        for item in recipes_dir.iterdir():
            if item.is_dir():
                recipe_file = item / "recipe.yaml"
                if recipe_file.exists():
                    recipe_files.append(recipe_file)
    return sorted(recipe_files)


def list_available_packages(recipes_dir: Path) -> None:
    """List all available packages and exit."""
    recipe_files = find_recipe_files(recipes_dir)

    print("📦 Available packages:")
    for recipe_file in recipe_files:
        package_name = recipe_file.parent.name
        try:
            with open(recipe_file, 'r', encoding='utf-8') as f:
                recipe = yaml.safe_load(f)
            current_version = recipe.get('context', {}).get('version', 'unknown')
            print(f"   • {package_name} (v{current_version})")
        except Exception:
            print(f"   • {package_name} (version unknown)")

    print(f"\n📊 Total: {len(recipe_files)} packages")


async def check_conda_forge_status_only(recipes_dir: Path, package_names: Optional[List[str]] = None,
                                       newer_only: bool = False, quiet: bool = False, json_output: bool = False) -> None:
    """Check conda-forge status only, skip upstream checks."""
    recipe_files = find_recipe_files(recipes_dir)

    if package_names:
        # Filter to specific packages
        filtered_files = []
        for name in package_names:
            recipe_file = recipes_dir / name / "recipe.yaml"
            if recipe_file.exists():
                filtered_files.append(recipe_file)
            else:
                print(f"Package '{name}' not found")
        recipe_files = filtered_files

    if not recipe_files:
        print("No recipe files found to process")
        return

    results = {}
    stats = UpdateStats()

    for recipe_file in recipe_files:
        try:
            with open(recipe_file, 'r', encoding='utf-8') as f:
                recipe = yaml.safe_load(f)

            package_name = recipe['package']['name']
            current_version = recipe['context']['version']

            conda_info = await check_package_on_conda_forge(package_name, current_version)

            if conda_info['exists_on_conda_forge']:
                stats.packages_on_conda_forge += 1
            else:
                stats.packages_not_on_conda_forge += 1

            results[package_name] = {
                'current_version': current_version,
                'conda_forge': conda_info
            }

            stats.total_packages += 1

        except Exception as e:
            stats.add_error(recipe_file.name, str(e))

    if json_output:
        print(json.dumps(results, indent=2))
    else:
        stats.print_summary()


def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Version control for meso-forge packages using APIs",
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

    # Mutually exclusive group for target selection
    target_group = parser.add_mutually_exclusive_group(required=True)
    target_group.add_argument('--all', '-a', action='store_true',
                              help='Check all packages in the recipes directory')
    target_group.add_argument('--package', '-p', action='append', dest='package_names', metavar='NAME',
                              help='Check specific package(s) (can be used multiple times)')
    target_group.add_argument('--list-packages', '-l', action='store_true',
                              help='List all available packages and exit')

    # Action options
    parser.add_argument('--update', '-u', action='store_true',
                        help='Actually update recipe files (default is check-only mode)')
    parser.add_argument('--dry-run', '-n', action='store_true',
                        help='Show what would be updated without making changes')
    parser.add_argument('--conda-forge-only', '-c', action='store_true',
                        help='Only check conda-forge status, skip upstream checks')
    parser.add_argument('--newer-only', action='store_true',
                        help='Only show packages where newer versions are available')

    # Configuration options
    parser.add_argument('--recipes-dir', '-d', type=Path, default=Path('./pkgs'),
                        help='Directory containing recipe files (default: ./pkgs)')
    parser.add_argument('--quiet', '-q', action='store_true',
                        help='Reduce output verbosity')
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Increase output verbosity')
    parser.add_argument('--json', action='store_true',
                        help='Output results in JSON format')

    return parser.parse_args()


async def main() -> int:
    """Main function."""
    args = parse_arguments()

    # Validate recipes directory
    if not args.recipes_dir.exists():
        print(f"Error: Recipes directory '{args.recipes_dir}' does not exist")
        return 1

    # Handle list packages request
    if args.list_packages:
        list_available_packages(args.recipes_dir)
        return 0

    # Handle conda-forge only mode
    if args.conda_forge_only:
        await check_conda_forge_status_only(
            args.recipes_dir, args.package_names, args.newer_only, args.quiet, args.json
        )
        return 0

    # Find recipe files to process
    recipe_files = find_recipe_files(args.recipes_dir)

    if args.package_names:
        # Filter to specific packages
        filtered_files = []
        for name in args.package_names:
            recipe_file = args.recipes_dir / name / "recipe.yaml"
            if recipe_file.exists():
                filtered_files.append(recipe_file)
            else:
                print(f"Package '{name}' not found")
        recipe_files = filtered_files

    if not recipe_files:
        print("No recipe files found to process")
        return 1

    print(f"🔍 Found {len(recipe_files)} recipe file(s) to process")

    if args.dry_run:
        print("🧪 DRY RUN MODE - No files will be modified")
    elif args.update:
        print("🔄 UPDATE MODE - Files will be modified")
    else:
        print("👀 CHECK MODE - No files will be modified")

    stats = UpdateStats()

    for recipe_file in recipe_files:
        await update_recipe(recipe_file, stats, args.dry_run or not args.update, args.quiet)

    # Filter results if newer_only is requested
    if args.newer_only and stats.upstream_newer == 0 and len(stats.errors) == 0:
        print("✅ All packages are already up-to-date!")
        return 0

    if not args.json:
        stats.print_summary()

    # Return error code if there were errors
    return 1 if len(stats.errors) > 0 else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
