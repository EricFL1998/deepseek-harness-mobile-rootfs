#!/usr/bin/env python3
"""Print the runtimeVersion of the newest published rootfs release.

The build workflow compares this against the image it is about to build: when
the DSH engine and the bundled bridge plugin both match, there is nothing to
rebuild and nothing new for a fresh install to download.

Reads the release asset through the API rather than the
`releases/download/<tag>/<file>` URL, because that path is a redirect and a
silently failed download would look identical to "no baseline" — which would
turn the guard off without saying so.
"""
import json
import sys
import urllib.error
import urllib.request

RELEASES_API = (
    "https://api.github.com/repos/EricFL1998/deepseek-harness-mobile-rootfs/releases"
)
USER_AGENT = "rootfs-builder"
TIMEOUT_SECONDS = 30


def fetch(url: str) -> bytes:
    """GET one URL with the headers GitHub expects."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return response.read()


def latest_runtime_version() -> str:
    """runtimeVersion of the newest release, or an empty string when unreadable."""
    try:
        releases = json.loads(fetch(f"{RELEASES_API}?per_page=1").decode())
    except (urllib.error.URLError, ValueError) as error:
        print(f"cannot list releases: {error}", file=sys.stderr)
        return ""
    if not releases:
        return ""
    tag = releases[0].get("tag_name", "")
    if not tag:
        return ""
    try:
        release = json.loads(fetch(f"{RELEASES_API}/tags/{tag}").decode())
    except (urllib.error.URLError, ValueError) as error:
        print(f"cannot read release {tag}: {error}", file=sys.stderr)
        return ""
    asset = next(
        (item for item in release.get("assets", []) if item.get("name") == "rootfs-manifest.json"),
        None,
    )
    if asset is None:
        print(f"release {tag} has no rootfs-manifest.json", file=sys.stderr)
        return ""
    try:
        manifest = json.loads(fetch(asset["browser_download_url"]).decode())
    except (urllib.error.URLError, ValueError) as error:
        print(f"cannot read the manifest of {tag}: {error}", file=sys.stderr)
        return ""
    return manifest.get("runtimeVersion", "")


def main() -> None:
    print(latest_runtime_version())


if __name__ == "__main__":
    main()
