"""
RubyGems source plugin for version control.

This plugin handles RubyGems repositories and gem downloads.
"""

import re
import requests
from typing import List, Optional
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
from plugins_source import SourcePlugin, VersionInfo


class RubyGemsPlugin(SourcePlugin):
    """Plugin for handling RubyGems repositories."""

    @property
    def name(self) -> str:
        return "rubygems"

    @property
    def supported_schemes(self) -> List[str]:
        return [
            "https://rubygems.org",
            "https://gem.fury.io",
        ]

    def can_handle(self, source_url: str) -> bool:
        """Check if this plugin can handle the given URL."""
        return any(scheme in source_url for scheme in self.supported_schemes)

    def extract_source_info(self, source_url: str) -> dict:
        """Extract gem name from RubyGems URL."""
        try:
            if 'rubygems.org' in source_url:
                if '/gems/' in source_url:
                    # Extract from URL like https://rubygems.org/gems/gem-name
                    gem_name = source_url.split('/gems/')[1].split('/')[0]
                    return {'gem_name': gem_name}
                elif '/downloads/' in source_url:
                    # Extract from download URL like https://rubygems.org/downloads/gem-name-1.0.0.gem
                    # or template URL like https://rubygems.org/downloads/gem-name-${{ version }}.gem
                    filename = source_url.split('/downloads/')[1].split('/')[0]
                    if filename.endswith('.gem'):
                        filename = filename[:-4]

                    # Handle template URLs with version placeholders
                    if '${{ version }}' in filename:
                        gem_name = filename.replace('-${{ version }}', '')
                    elif '{{ version }}' in filename:
                        gem_name = filename.replace('-{{ version }}', '')
                    else:
                        # Try to extract gem name by removing version-like suffix
                        import re
                        # Remove version pattern from end (e.g., gem-name-1.2.3 -> gem-name)
                        gem_name = re.sub(r'-\d+(\.\d+)*.*$', '', filename)

                    return {'gem_name': gem_name}
                else:
                    # Fallback - extract from URL path
                    path_parts = source_url.split('/')
                    if len(path_parts) > 1:
                        gem_name = path_parts[-1]
                        if gem_name.endswith('.gem'):
                            gem_name = gem_name[:-4]
                        return {'gem_name': gem_name}

            # If we can't extract from URL, return empty dict
            # The caller should provide gem_name via package_name
            return {}
        except (IndexError, ValueError) as e:
            raise ValueError(f"Invalid RubyGems URL format: {source_url}") from e

    async def get_latest_version(
        self,
        source_url: str,
        package_name: str,
        version_patterns: Optional[List[str]] = None,
        mode: Optional[str] = None,
        quiet: bool = False,
        **kwargs
    ) -> Optional[VersionInfo]:
        """Get the latest version from RubyGems."""
        source_info = self.extract_source_info(source_url)
        gem_name = source_info.get('gem_name', package_name)

        return self._get_latest_gem_version(gem_name, package_name, version_patterns, quiet)

    def _get_latest_gem_version(
        self,
        gem_name: str,
        package_name: str,
        version_patterns: Optional[List[str]] = None,
        quiet: bool = False
    ) -> Optional[VersionInfo]:
        """Get latest gem version from RubyGems API."""
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
        except requests.exceptions.Timeout:
            if not quiet:
                print(f"({package_name}) Timeout fetching RubyGems info")
        except requests.exceptions.ConnectionError:
            if not quiet:
                print(f"({package_name}) Connection error fetching RubyGems info")
        except Exception as e:
            if not quiet:
                print(f"({package_name}) Error fetching RubyGems info: {e}")

        return None

    def get_gem_dependencies(self, gem_name: str, version: str | None = None) -> dict:
        """Get gem dependencies (useful for future enhancement)."""
        try:
            if version:
                api_url = f"https://rubygems.org/api/v1/gems/{gem_name}/versions/{version}.json"
            else:
                api_url = f"https://rubygems.org/api/v1/gems/{gem_name}.json"

            response = requests.get(api_url, timeout=30)
            if response.status_code == 200:
                gem_info = response.json()
                return gem_info.get('dependencies', {})
        except Exception:
            pass
        return {}

    def search_gems(self, query: str, limit: int = 10) -> List[dict]:
        """Search for gems (useful for future enhancement)."""
        try:
            api_url = f"https://rubygems.org/api/v1/search.json?query={query}&limit={limit}"
            response = requests.get(api_url, timeout=30)
            if response.status_code == 200:
                return response.json()
        except Exception:
            pass
        return []
