"""
Git source plugin for version control.

This plugin handles general Git repositories that aren't specifically GitHub,
GitLab, or other specialized Git hosting services.
"""

import re
import subprocess
from typing import List, Optional
from urllib.parse import urlparse
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
from plugins_source import SourcePlugin, VersionInfo


class GitPlugin(SourcePlugin):
    """Plugin for handling general Git repositories."""

    @property
    def name(self) -> str:
        return "git"

    @property
    def supported_schemes(self) -> List[str]:
        return [
            "git://",
            "git+https://",
            "git+ssh://",
            "ssh://git@",
        ]

    def can_handle(self, source_url: str) -> bool:
        """Check if this plugin can handle the given URL."""
        # Handle git-specific schemes
        if any(scheme in source_url for scheme in self.supported_schemes):
            return True

        # Handle URLs that end with .git but aren't GitHub/GitLab
        if source_url.endswith('.git'):
            parsed = urlparse(source_url)
            # Exclude known hosting services (handled by their specific plugins)
            excluded_hosts = ['github.com', 'gitlab.com', 'bitbucket.org']
            return parsed.netloc not in excluded_hosts

        return False

    def extract_source_info(self, source_url: str) -> dict:
        """Extract repository information from Git URL."""
        try:
            parsed = urlparse(source_url)

            # Clean up the URL for cloning
            clone_url = source_url
            if clone_url.startswith('git+'):
                clone_url = clone_url[4:]  # Remove 'git+' prefix

            # Extract repo name from path
            path = parsed.path
            if path.endswith('.git'):
                path = path[:-4]

            repo_name = path.split('/')[-1] if path else 'unknown'

            return {
                'clone_url': clone_url,
                'repo_name': repo_name,
                'host': parsed.netloc
            }
        except Exception as e:
            raise ValueError(f"Invalid Git URL format: {source_url}") from e

    async def get_latest_version(
        self,
        source_url: str,
        package_name: str,
        version_patterns: Optional[List[str]] = None,
        mode: Optional[str] = None,
        quiet: bool = False,
        **kwargs
    ) -> Optional[VersionInfo]:
        """Get the latest version from Git repository."""
        source_info = self.extract_source_info(source_url)
        clone_url = source_info['clone_url']

        if mode == 'git-tags':
            return self._get_latest_tag(clone_url, package_name, version_patterns, quiet)
        elif mode == 'git-branches':
            return self._get_latest_branch(clone_url, package_name, version_patterns, quiet)
        else:
            # Default: try tags first, then main/master branch
            version_info = self._get_latest_tag(clone_url, package_name, version_patterns, quiet)
            if version_info is None:
                if not quiet:
                    print(f"({package_name}) No matching tags found, trying default branch...")
                version_info = self._get_latest_branch(clone_url, package_name, version_patterns, quiet)
            return version_info

    def _get_latest_tag(
        self,
        clone_url: str,
        package_name: str,
        version_patterns: Optional[List[str]] = None,
        quiet: bool = False
    ) -> Optional[VersionInfo]:
        """Get latest tag from Git repository."""
        if not version_patterns:
            version_patterns = [r'^v?(\d+\.\d+\.\d+)']

        try:
            # Use git ls-remote to get tags without cloning
            result = subprocess.run(
                ['git', 'ls-remote', '--tags', '--sort=-version:refname', clone_url],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode != 0:
                if not quiet:
                    print(f"({package_name}) Failed to fetch tags: {result.stderr}")
                return None

            tags = []
            for line in result.stdout.strip().split('\n'):
                if not line:
                    continue

                parts = line.split('\t')
                if len(parts) != 2:
                    continue

                commit_hash, ref = parts
                if not ref.startswith('refs/tags/'):
                    continue

                tag_name = ref.replace('refs/tags/', '')

                # Skip tag references that point to other tags (^{})
                if tag_name.endswith('^{}'):
                    continue

                tags.append((tag_name, commit_hash))

            if not tags:
                if not quiet:
                    print(f"({package_name}) No tags found in repository")
                return None

            # Find valid tags matching patterns
            valid_tags = []
            for tag_name, commit_hash in tags:
                cleaned_tag = self._clean_tag_name(tag_name, package_name)

                for pattern in version_patterns:
                    try:
                        match = re.match(pattern, cleaned_tag)
                        if match:
                            version = match.group(1) if match.groups() else match.group(0)

                            # Create archive URL (this is repository-specific)
                            download_url = self._create_archive_url(clone_url, tag_name)

                            valid_tags.append(VersionInfo(
                                version=version,
                                download_url=download_url,
                                tag_name=tag_name,
                                source_type="git"
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

            # Return the first (most recent) matching tag
            latest = valid_tags[0]
            if not quiet:
                print(f"({package_name}) Found {len(valid_tags)} matching tags, latest: {latest.version}")
                print(f"({package_name}) Download URL: {latest.download_url}")

            return latest

        except subprocess.TimeoutExpired:
            if not quiet:
                print(f"({package_name}) Timeout fetching Git tags")
        except FileNotFoundError:
            if not quiet:
                print(f"({package_name}) Git command not found")
        except Exception as e:
            if not quiet:
                print(f"({package_name}) Error fetching Git tags: {e}")

        return None

    def _get_latest_branch(
        self,
        clone_url: str,
        package_name: str,
        version_patterns: Optional[List[str]] = None,
        quiet: bool = False
    ) -> Optional[VersionInfo]:
        """Get latest commit from default branch."""
        try:
            # Get default branch
            result = subprocess.run(
                ['git', 'ls-remote', '--symref', clone_url, 'HEAD'],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode != 0:
                if not quiet:
                    print(f"({package_name}) Failed to fetch branch info: {result.stderr}")
                return None

            # Parse the output to find default branch and latest commit
            lines = result.stdout.strip().split('\n')
            default_branch = 'main'  # fallback
            commit_hash = None

            for line in lines:
                if line.startswith('ref: refs/heads/'):
                    default_branch = line.split('refs/heads/')[1].split('\t')[0]
                elif '\trefs/heads/' in line or '\tHEAD' in line:
                    commit_hash = line.split('\t')[0]

            if not commit_hash:
                if not quiet:
                    print(f"({package_name}) Could not determine latest commit")
                return None

            # For branches, we'll use the commit hash as version
            # This is a fallback when no tags are available
            version = commit_hash[:8]  # Short hash
            download_url = self._create_archive_url(clone_url, default_branch)

            if not quiet:
                print(f"({package_name}) Using latest commit from {default_branch}: {version}")
                print(f"({package_name}) Download URL: {download_url}")

            return VersionInfo(
                version=version,
                download_url=download_url,
                tag_name=default_branch,
                source_type="git"
            )

        except subprocess.TimeoutExpired:
            if not quiet:
                print(f"({package_name}) Timeout fetching Git branch info")
        except FileNotFoundError:
            if not quiet:
                print(f"({package_name}) Git command not found")
        except Exception as e:
            if not quiet:
                print(f"({package_name}) Error fetching Git branch info: {e}")

        return None

    def _clean_tag_name(self, tag_name: str, package_name: str) -> str:
        """Clean up tag name for version extraction."""
        cleaned_tag = tag_name
        if cleaned_tag.startswith(package_name):
            cleaned_tag = cleaned_tag[len(package_name)+1:]
        if cleaned_tag.startswith('v'):
            cleaned_tag = cleaned_tag[1:]
        return cleaned_tag

    def _create_archive_url(self, clone_url: str, ref: str) -> str:
        """Create archive download URL for the repository."""
        # This is a generic implementation
        # Different Git hosting services have different archive URL formats

        # For generic Git repositories, we'll return the clone URL with ref info
        # The actual implementation would depend on the hosting service
        return f"{clone_url}#ref={ref}"

    def clone_repository(self, clone_url: str, target_dir: str, ref: str | None = None) -> bool:
        """Clone repository to target directory (utility function)."""
        try:
            cmd = ['git', 'clone']
            if ref:
                cmd.extend(['--branch', ref])
            cmd.extend([clone_url, target_dir])

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            return result.returncode == 0

        except Exception:
            return False

    def get_commit_info(self, clone_url: str, commit_hash: str) -> dict:
        """Get information about a specific commit (utility function)."""
        try:
            result = subprocess.run(
                ['git', 'ls-remote', clone_url, commit_hash],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode == 0 and result.stdout.strip():
                return {'commit_hash': commit_hash, 'exists': True}

        except Exception:
            pass

        return {'commit_hash': commit_hash, 'exists': False}
