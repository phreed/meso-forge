import os
import sys
import yaml
import requests
from pathlib import Path
import hashlib
import semver


def get_github_latest_commit(group: str, repo: str, package_name: str):
    """Get latest release version from GitHub."""
    api_url = f"https://api.github.com/repos/{repo}/commits/latest"
    # Use GitHub token if available
    token = os.getenv('GITHUB_TOKEN')
    headers = {}
    if token:
        headers['Authorization'] = f'token {token}'

    response = requests.get(api_url, headers=headers)
    if response.status_code == 200:
        tag_name = response.json()['tag_name']

        if tag_name.startswith(package_name):
            tag_name = tag_name[len(package_name)+1:]
    
        return tag_name
    return None


def get_github_latest_release(group: str, repo: str, package_name: str):
    """
    Get latest release version from GitHub.
    https://docs.github.com/en/rest/releases/releases?apiVersion=2022-11-28#list-releases
    """
    api_url = f"https://api.github.com/repos/{group}/{repo}/releases/latest"

    # Use GitHub token if available
    token = os.getenv('GITHUB_TOKEN')
    headers = {}
    if token:
        headers['Authorization'] = f'token {token}'

    response = requests.get(api_url, headers=headers)
    match response.status_code:
        case 200:
            resp_json = response.json()
            tag_name = resp_json['tag_name']

            if tag_name.startswith(package_name):
                tag_name = tag_name[len(package_name)+1:]
            if tag_name.startswith('v'):
                tag_name = tag_name[1:]
        
            return tag_name
        case 404:
            print(f"({package_name}) Could not fetch {api_url} ")
        case _:    
            print(f"({package_name}) Could not fetch {response.status_code} ")

    return None


def get_github_latest_tag(group: str, repo: str, package_name: str):
    """
    Get latest tagged version from GitHub.
    https://docs.github.com/en/rest/git/tags?apiVersion=2022-11-28#about-git-tags
    """
    api_url = f"https://api.github.com/repos/{group}/{repo}/tags"

    # Use GitHub token if available
    token = os.getenv('GITHUB_TOKEN')
    headers = {}
    if token:
        headers['Authorization'] = f'token {token}'

    response = requests.get(api_url, headers=headers)
    match response.status_code:
        case 200:
            tag_name = None
            tag = None
            resp_json = response.json()
            # print(f"Response: {resp_json}")
            for item in resp_json:
                candidate = item['name']
                if candidate.startswith(package_name):
                    candidate = candidate[len(package_name)+1:]
                if candidate.startswith('v'):
                    candidate = candidate[1:]
                print(candidate)
                if  tag_name is None:
                    tag_name = candidate
                    tag = item
                else:
                    try:
                        match semver.compare(candidate, tag_name):
                            case 1:
                                tag_name = candidate
                                tag = item
                            case 0:
                                pass
                            case -1:
                                pass
                    except:
                        pass                  
                    
            return tag_name
        case 404:
            print(f"({package_name}) Could not fetch {api_url} ")
        case 403:    
            print(f"({package_name}) Could not fetch {api_url} because {response.status_code} ")
        case _:    
            print(f"({package_name}) Could not fetch {api_url} because {response.status_code} ")

    return None

def calculate_sha256(url):
    """Download file and calculate SHA256."""
    response = requests.get(url, stream=True)
    if response.status_code == 200:
        sha256_hash = hashlib.sha256()
        for chunk in response.iter_content(chunk_size=8192):
            sha256_hash.update(chunk)
        return sha256_hash.hexdigest()
    return None

def replace_version_string(content, new_version):
    """Replace first occurrence of version in content, line by line."""
    lines = content.splitlines()
    for i, line in enumerate(lines):
        if line.strip().startswith('version:'):
            # Keep the leading whitespace
            whitespace = line[:line.index('version:')]
            lines[i] = f'{whitespace}version: "{new_version}"'
            break
    return '\n'.join(lines)


def update_recipe_release(recipe_path, recipe, current_version, package_name, release_url):
    # Determine package source
    if 'github.com' in release_url:
        # Extract owner/repo from GitHub URL
        group, repo = release_url.split('github.com/')[1].split('/')[0:2]
        new_version = get_github_latest_release(group, repo, package_name)
        if new_version is None:
            new_version = get_github_latest_tag(group, repo, package_name)

    elif 'pypi.org' in release_url:
        print(f"({package_name}) PyPi not yet supported source URL format: {release_url}")
        return None
    elif 'registry.npmjs.org' in release_url:
        print(f"({package_name}) npm registry not yet supported source URL format: {release_url}")
        return None
    else:
        print(f"({package_name}) Unsupported source URL format: {release_url}")
        return None

    if new_version == current_version:
        print(f"({package_name}) Already at latest version: {current_version}")
        return None

    print(f"({package_name}) Checking package {recipe['package']['name']} for updates")
    print(f"({package_name}) Current version: {current_version}, Latest version: {new_version}")
    # Update URL and calculate new hash
    if new_version is None:
        print(f"no new version is supplied, it seems to be None")
        new_url = None
    else:
        new_url = release_url.replace("${{ version }}", new_version)
    new_hash = calculate_sha256(new_url)

    if not new_hash:
        print(f"({package_name}) Failed to calculate new hash for {recipe_path}")
        return None

    return (new_version, new_url, new_hash)


def update_recipe_commit(recipe_path, recipe, current_version, package_name, repo_url):
    """
    Determine package source
    """
    if 'github.com' in repo_url:
        # Extract owner/repo from GitHub URL
        repo = '/'.join(repo_url.split('github.com/')[1].split('/')[0:2])
        new_version = get_github_latest_commit(repo, package_name)
    else:
        print(f"({package_name}) Unsupported source URL format: {repo_url}")
        return None

    if new_version == current_version:
        print(f"({package_name}) Already at latest version: {current_version}")
        return None

    print(f"({package_name}) Checking package {recipe['package']['name']} for updates")
    print(f"({package_name}) Current revision: {current_version}, Latest revision: {new_version}")
    # Update URL and calculate new hash
    new_url = repo_url
    new_hash = calculate_sha256(new_url)

    if not new_hash:
        print(f"({package_name}) Failed to calculate new hash for {recipe_path}")
        return None

    return (new_version, new_url, new_hash)

def update_source(recipe_path, recipe, current_version, package_name, source):
    """Update version and hash in easch source"""
    if 'if' in source:
        source = source['then']
    if 'path' in source:
        print(f"local path")
        return
    if 'url' in source:
        release_url = source['url']
        old_hash = source['sha256']
        result = update_recipe_release(recipe_path, recipe, current_version, package_name, release_url)
        if result is None:
            return
        new_version, new_url, new_hash = result
        # Update recipe as a string replace because we want to keep all YAML formatting
        release_url = new_url
        recipe_str = recipe_path.read_text()
        recipe_str = replace_version_string(recipe_str, new_version)
        recipe_str = recipe_str.replace(old_hash, new_hash)

        print(f"({package_name}) Updated {recipe_path}: {current_version} -> {new_version}")

    elif 'git' in source:
        repo_url = source['git']
        old_hash = source['rev']
        update_recipe_commit(recipe_path, recipe, current_version, old_hash, package_name, repo_url)
        if result is None:
            return
        new_version, new_url, new_hash = result
        repo_url = new_url
        recipe_str = recipe_path.read_text()
        recipe_str = replace_version_string(recipe_str, new_version)
        recipe_str = recipe_str.replace(old_hash, new_hash)

        print(f"({package_name}) Updated {recipe_path}: {current_version} -> {new_version}")
    else:
        print(f"({package_name}) unknown source url must be one of ('git', 'url')")
        return

    # Save updated recipe
    recipe_path.write_text(recipe_str.strip())


def update_recipe(recipe_path):
    """Update version and hash in recipe file."""
    with open(recipe_path) as f:
        recipe = yaml.safe_load(f)

    current_version = recipe['context']['version']
    package_name = recipe['package']['name']

    sources = recipe['source']
    if isinstance(sources, dict):
        update_source(recipe_path, recipe, current_version, package_name, sources)
        return
    elif isinstance(sources, list):
        if all(isinstance(item, dict) for item in sources):
            update_source(recipe_path, recipe, current_version, package_name, sources)
        else:
            update_source(recipe_path, recipe, current_version, package_name, sources)
        return
    else:
        print(f"({package_name}) sources is neither list nor dictionary.")
        return None

def main():
    recipe_dir = Path('./packages')

    # take first arg from cli and use as recipe_dir
    if len(sys.argv) > 1:
        recipe_dir = Path(sys.argv[1])

    for recipe_file in recipe_dir.glob('**/recipe.yaml'):
        try:
            update_recipe(recipe_file)
        except Exception as e:
            print(f"Error processing {recipe_file}: {e}")

if __name__ == '__main__':
    main()
