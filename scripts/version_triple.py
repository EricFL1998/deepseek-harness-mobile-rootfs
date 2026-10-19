#!/usr/bin/env python3
"""Print the `dsh|bridge` pair from a rootfs runtimeVersion.

The image's version string carries three segments:

    1.1.0-dsh0.2.1-rc.2-bridge1.1.0

A rebuild is warranted when either the DSH engine or the bundled bridge plugin
moved, so the build workflow compares this pair against the newest published
image's pair. The rootfs number itself is bookkeeping: it advances whenever the
image is rebuilt, and comparing it would report a change every time.

A missing segment prints as an empty field, so an image built before the bridge
segment existed never compares equal to one that has it.
"""
import re
import sys


def triple(text: str) -> str:
    """Return `<dsh>|<bridge>` for one runtimeVersion string."""
    bridge = re.search(r"-bridge(\S+)$", text)
    rest = text[: bridge.start()] if bridge else text
    dsh = re.search(r"-dsh(\S+)$", rest)
    return "%s|%s" % (
        dsh.group(1) if dsh else "",
        bridge.group(1) if bridge else "",
    )


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: version_triple.py <runtimeVersion>", file=sys.stderr)
        sys.exit(1)
    print(triple(sys.argv[1].strip()))


if __name__ == "__main__":
    main()
