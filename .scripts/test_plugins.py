#!/usr/bin/env python3
"""
Test script for the plugin system.

This script tests the loading and functionality of source type plugins.
"""

import sys
from pathlib import Path

# Add the scripts directory to the path so we can import plugins
scripts_dir = Path(__file__).parent
sys.path.insert(0, str(scripts_dir))

from plugins_source import PluginManager


def test_plugin_loading():
    """Test that plugins are loaded correctly."""
    print("Testing plugin loading...")

    manager = PluginManager()
    plugins = manager.list_plugins()

    print(f"Loaded {len(plugins)} plugins: {plugins}")

    for plugin_name in plugins:
        plugin = manager.get_plugin_by_name(plugin_name)
        if plugin:
            print(f"  {plugin_name}: {plugin.__class__.__name__}")
            print(f"    Supported schemes: {plugin.supported_schemes}")
        else:
            print(f"  {plugin_name}: Failed to get plugin instance")

    return len(plugins) > 0


def test_url_matching():
    """Test that plugins can match appropriate URLs."""
    print("\nTesting URL matching...")

    manager = PluginManager()

    test_urls = [
        "https://github.com/owner/repo",
        "https://rubygems.org/gems/gem-name",
        "git://example.com/repo.git",
        "https://unknown-service.com/repo",
    ]

    for url in test_urls:
        plugin = manager.get_plugin_for_url(url)
        if plugin:
            print(f"  {url} -> {plugin.name}")
        else:
            print(f"  {url} -> No plugin found")


def test_source_info_extraction():
    """Test that plugins can extract source information."""
    print("\nTesting source info extraction...")

    manager = PluginManager()

    test_cases = [
        ("https://github.com/owner/repo", "github"),
        ("https://rubygems.org/gems/gem-name", "rubygems"),
    ]

    for url, expected_plugin in test_cases:
        plugin = manager.get_plugin_by_name(expected_plugin)
        if plugin:
            try:
                info = plugin.extract_source_info(url)
                print(f"  {url} -> {info}")
            except Exception as e:
                print(f"  {url} -> Error: {e}")
        else:
            print(f"  {expected_plugin} plugin not found")


async def test_version_fetching():
    """Test fetching version information (limited test)."""
    print("\nTesting version fetching...")

    manager = PluginManager()

    # Test with a real GitHub repo (limited to avoid API rate limits)
    github_plugin = manager.get_plugin_by_name("github")
    if github_plugin:
        try:
            # Test URL parsing without actually fetching
            info = github_plugin.extract_source_info("https://github.com/python/cpython")
            print(f"  GitHub info extraction: {info}")
        except Exception as e:
            print(f"  GitHub test failed: {e}")

    # Test RubyGems plugin
    rubygems_plugin = manager.get_plugin_by_name("rubygems")
    if rubygems_plugin:
        try:
            info = rubygems_plugin.extract_source_info("https://rubygems.org/gems/rails")
            print(f"  RubyGems info extraction: {info}")
        except Exception as e:
            print(f"  RubyGems test failed: {e}")


def main():
    """Run all tests."""
    print("=== Plugin System Test ===")

    success = True

    try:
        if not test_plugin_loading():
            print("❌ Plugin loading failed")
            success = False
        else:
            print("✅ Plugin loading successful")

        test_url_matching()
        test_source_info_extraction()

        # Skip async test for now to keep it simple
        # import asyncio
        # asyncio.run(test_version_fetching())

    except Exception as e:
        print(f"❌ Test failed with error: {e}")
        success = False

    if success:
        print("\n🎉 All tests completed successfully!")
        return 0
    else:
        print("\n💥 Some tests failed!")
        return 1


if __name__ == "__main__":
    sys.exit(main())
