"""
Plugin interface for version control source types.

This module defines the base interface for source type plugins using a custom system.
Each source type (GitHub, RubyGems, Git, etc.) implements this interface.
"""

import importlib
import importlib.util
import os
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Optional, List, NamedTuple, Dict, Type


class VersionInfo(NamedTuple):
    """Container for version information from APIs."""
    version: str
    download_url: Optional[str] = None
    tag_name: Optional[str] = None
    source_type: str = "unknown"
    asset_name: Optional[str] = None


class SourcePlugin(ABC):
    """Base class for all source type plugins."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Return the name of this source plugin."""
        pass

    @property
    @abstractmethod
    def supported_schemes(self) -> List[str]:
        """Return list of URL schemes this plugin supports (e.g., ['https://github.com'])."""
        pass

    @abstractmethod
    def can_handle(self, source_url: str) -> bool:
        """Return True if this plugin can handle the given source URL."""
        pass

    @abstractmethod
    async def get_latest_version(
        self,
        source_url: str,
        package_name: str,
        version_patterns: Optional[List[str]] = None,
        mode: Optional[str] = None,
        quiet: bool = False,
        **kwargs
    ) -> Optional[VersionInfo]:
        """Get the latest version information from the source."""
        pass

    @abstractmethod
    def extract_source_info(self, source_url: str) -> dict:
        """Extract relevant information from the source URL (e.g., owner/repo for GitHub)."""
        pass


class PluginManager:
    """Manager for loading and using source plugins."""

    def __init__(self):
        self._plugins: Dict[str, SourcePlugin] = {}
        self._load_plugins()

    def _load_plugins(self):
        """Load all available source plugins."""
        # Get the directory containing this file
        plugins_dir = Path(__file__).parent

        # Import all plugin modules
        for plugin_file in plugins_dir.glob("*_plugin.py"):
            module_name = plugin_file.stem
            try:
                # Import the plugin module
                spec = importlib.util.spec_from_file_location(
                    f"plugins_source.{module_name}", plugin_file
                )
                if spec and spec.loader:
                    module = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(module)

                    # Find plugin classes in the module
                    for attr_name in dir(module):
                        attr = getattr(module, attr_name)
                        if (isinstance(attr, type) and
                            issubclass(attr, SourcePlugin) and
                            attr != SourcePlugin):
                            # Instantiate the plugin
                            plugin = attr()
                            self._plugins[plugin.name] = plugin

            except Exception as e:
                print(f"Warning: Failed to load plugin {module_name}: {e}")

    def get_plugin_for_url(self, source_url: str) -> Optional[SourcePlugin]:
        """Get the appropriate plugin for a given source URL."""
        for plugin in self._plugins.values():
            if plugin.can_handle(source_url):
                return plugin
        return None

    def get_plugin_by_name(self, name: str) -> Optional[SourcePlugin]:
        """Get a plugin by its name."""
        return self._plugins.get(name)

    def list_plugins(self) -> List[str]:
        """List all available plugin names."""
        return list(self._plugins.keys())

    async def get_latest_version(
        self,
        source_url: str,
        package_name: str,
        version_patterns: Optional[List[str]] = None,
        mode: Optional[str] = None,
        quiet: bool = False,
        **kwargs
    ) -> Optional[VersionInfo]:
        """Get latest version using the appropriate plugin."""
        plugin = self.get_plugin_for_url(source_url)
        if not plugin:
            if not quiet:
                print(f"({package_name}) No plugin found for URL: {source_url}")
            return None

        return await plugin.get_latest_version(
            source_url, package_name, version_patterns, mode, quiet, **kwargs
        )


# Global plugin manager instance
plugin_manager = PluginManager()
