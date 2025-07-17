"""
GitHub source plugin for version control.

This plugin handles GitHub repositories, supporting releases, tags, and assets.
"""

import os
import re
import requests
import semver
from typing import List, Optional
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
from plugins_source import SourcePlugin, VersionInfo


class GitHubPlugin(SourcePlugin):
    """Plugin for handling GitHub repositories."""

    @property
    def name(self) -> str:
        return "github"

    @property
    def supported_schemes(self) -> List[str]:
        return [
            "https://github.com",
            "https://api.github.com",
            "git+https://github.com",
        ]

    def can_handle(self, source_url: str) -> bool:
        """Check if this plugin can handle the given URL."""
        return any(scheme in source_url for scheme in self.supported_schemes)

    def extract_source_info(self, source_url: str) -> dict:
        """Extract owner and repo from GitHub URL."""
        try:
            if 'api.github.com/repos/' in source_url:
                # Handle GitHub API URLs like https://api.github.com/repos/owner/repo/...
                parts = source_url.split('api.github.com/repos/')[1].split('/')
                owner, repo = parts[0], parts[1]
            else:
                # Handle regular GitHub URLs like https://github.com/owner/repo
                parts = source_url.split('github.com/')[1].split('/')
                owner, repo = parts[0], parts[1]
                # Remove .git suffix if present
                if repo.endswith('.git'):
                    repo = repo[:-4]

            return {'owner': owner, 'repo': repo}
        except (IndexError, ValueError) as e:
            raise ValueError(f"Invalid GitHub URL format: {source_url}") from e

    async def get_latest_version(
        self,
        source_url: str,
        package_name: str,
        version_patterns: Optional[List[str]] = None,
        mode: Optional[str] = None,
        quiet: bool = False,
        **kwargs
    ) -> Optional[VersionInfo]:
        """Get the latest version from GitHub."""
        source_info = self.extract_source_info(source_url)
        owner = source_info['owner']
        repo = source_info['repo']

        # Determine the specific GitHub mode
        if mode == 'github-tags':
            return self._get_latest_tag(owner, repo, package_name, version_patterns, quiet)
        elif mode == 'github-release':
            return self._get_latest_release(owner, repo, package_name, version_patterns, quiet)

        else:
            # Auto-detect: try releases first, then tags as fallback
            version_info = self._get_latest_release(owner, repo, package_name, version_patterns, quiet)
            if version_info is None:
                if not quiet:
                    print(f"({package_name}) No matching releases found, trying tags...")
                version_info = self._get_latest_tag(owner, repo, package_name, version_patterns, quiet)
            return version_info

    def _get_headers(self) -> dict:
        """Get headers for GitHub API requests."""
        headers = {}
        token = os.getenv('GITHUB_TOKEN')
        if token:
            headers['Authorization'] = f'token {token}'
        return headers

    def _get_latest_release(
        self,
        owner: str,
        repo: str,
        package_name: str,
        version_patterns: Optional[List[str]] = None,
        quiet: bool = False
    ) -> Optional[VersionInfo]:
        """Get latest release version from GitHub releases API."""
        api_url = f"https://api.github.com/repos/{owner}/{repo}/releases"

        # Default version pattern if none provided
        if not version_patterns:
            version_patterns = [r'^(\d+\.\d+\.\d+)']

        headers = self._get_headers()

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
                    cleaned_tag = self._clean_tag_name(tag_name, package_name)

                    # Check if version matches any of the patterns
                    for pattern in version_patterns:
                        try:
                            match = re.match(pattern, cleaned_tag)
                            if match:
                                # Extract the version (first capture group or full match)
                                version = match.group(1) if match.groups() else match.group(0)

                                # Construct the release URL
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
                return self._sort_and_get_latest(valid_releases, package_name, quiet)

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

    def _get_latest_tag(
        self,
        owner: str,
        repo: str,
        package_name: str,
        version_patterns: Optional[List[str]] = None,
        quiet: bool = False
    ) -> Optional[VersionInfo]:
        """Get latest tag version from GitHub tags API."""
        api_url = f"https://api.github.com/repos/{owner}/{repo}/tags"

        # Default version pattern if none provided
        if not version_patterns:
            version_patterns = [r'^(\d+\.\d+\.\d+)']

        headers = self._get_headers()

        try:
            response = requests.get(api_url, headers=headers, timeout=30)
            if response.status_code == 200:
                tags = response.json()

                if not tags:
                    if not quiet:
                        print(f"({package_name}) No tags found for {owner}/{repo}")
                    return None

                if not quiet:
                    print(f"({package_name}) Found {len(tags)} total tags")

                valid_tags = []

                for tag in tags:
                    tag_name = tag.get('name', '')
                    if not tag_name:
                        continue

                    # Clean up tag name for version extraction
                    cleaned_tag = self._clean_tag_name(tag_name, package_name)

                    # Check if version matches any of the patterns
                    for pattern in version_patterns:
                        try:
                            match = re.match(pattern, cleaned_tag)
                            if match:
                                # Extract the version (first capture group or full match)
                                version = match.group(1) if match.groups() else match.group(0)

                                # Construct the release URL
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
                return self._sort_and_get_latest(valid_tags, package_name, quiet)

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

    def _clean_tag_name(self, tag_name: str, package_name: str) -> str:
        """Clean up tag name for version extraction."""
        # Remove common prefixes like 'v', 'V', 'version', 'release', or package name
        cleaned = tag_name
        prefixes = ['v', 'V', 'version', 'release', 'Release', 'VERSION', 'RELEASE']
        for prefix in prefixes:
            if cleaned.lower().startswith(prefix.lower()):
                cleaned = cleaned[len(prefix):]
                break
        return cleaned

    def _sort_and_get_latest(
        self,
        versions: List[VersionInfo],
        package_name: str,
        quiet: bool = False
    ) -> Optional[VersionInfo]:
        """Sort versions and return the latest."""
        if not versions:
            return None

        try:
            # Sort by semantic version
            versions.sort(key=lambda x: semver.VersionInfo.parse(x.version), reverse=True)
            latest = versions[0]
            if not quiet:
                print(f"({package_name}) Found {len(versions)} matching versions, latest: {latest.version}")
                print(f"({package_name}) Download URL: {latest.download_url}")
            return latest
        except (ValueError, TypeError) as e:
            if not quiet:
                print(f"({package_name}) Error parsing semantic versions, using string sort: {e}")
            # Fallback to string sort
            versions.sort(key=lambda x: x.version, reverse=True)
            return versions[0]
