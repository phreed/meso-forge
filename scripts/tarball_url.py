import requests

owner = "sharkdp"
repo = "fd"
tag = "v10.2.0"

release_api_url = f"https://api.github.com/repos/{owner}/{repo}/releases"
response = requests.get(release_api_url)
releases = response.json()

tarball_url = None
for release in releases:
    if release.get("tag_name") == tag:
        tarball_url = release.get("tarball_url")
        break

if tarball_url:
    print(f"API tarball_url: {tarball_url}")
    # Make a request to the tarball_url, allow redirects
    download_response = requests.get(tarball_url, allow_redirects=True)

    # The final URL after redirects is in download_response.url
    actual_download_url = download_response.url
    print(f"Actual download URL (after redirect): {actual_download_url}")

    # You can then save the content if needed
    # with open(f"{repo}-{tag}.tar.gz", "wb") as f:
    #     f.write(download_response.content)
else:
    print(f"Release with tag '{tag}' not found.")
