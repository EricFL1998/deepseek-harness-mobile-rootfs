import json
import re
import urllib.request
import sys

def get_latest_github_release_tag():
    url = "https://api.github.com/repos/EricFL1998/deepseek-harness-mobile-rootfs/releases?per_page=20"
    req = urllib.request.Request(url, headers={"User-Agent": "rootfs-builder"})
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            for rel in data:
                tag = rel.get("tag_name", "")
                m = re.match(r"^rootfs-v(\d+)\.(\d+)\.(\d+)", tag)
                if m:
                    return int(m.group(1)), int(m.group(2)), int(m.group(3))
    except Exception as e:
        print(f"Notice: failed to fetch releases (might be new repo without releases): {e}")
    return 1, 0, 0

def get_latest_dsh_npm_version():
    url = "https://registry.npmjs.org/@deepseek-ai/dsh"
    req = urllib.request.Request(url, headers={"User-Agent": "rootfs-builder"})
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode())
        dist_tags = data.get("dist-tags", {})
        versions = list(data.get("versions", {}).keys())

        # 1. 优先检查 dist-tags.next 或 dist-tags.latest 是否为 rc 版本
        for tag in ["next", "latest"]:
            v = dist_tags.get(tag, "")
            if re.search(r"-rc\.\d+$", v):
                return v

        # 2. 从所有已发布的版本列表中逆序筛选最新的 rc 版本 (忽略 alpha / dev 等预发布版本)
        rc_versions = [v for v in versions if re.search(r"-rc\.\d+$", v)]
        if rc_versions:
            return rc_versions[-1]

        # 3. 兜底
        return dist_tags.get("latest", "0.2.1-rc.2")

if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "resolve"
    if action == "npm_dsh":
        print(get_latest_dsh_npm_version())
    elif action == "next_rootfs_ver":
        maj, min_v, pat = get_latest_github_release_tag()
        # if no releases exist yet, start at 1.0.0, else bump patch
        # Check if 1.0.0 exists
        url = "https://api.github.com/repos/EricFL1998/deepseek-harness-mobile-rootfs/releases/tags/rootfs-v1.0.0"
        req = urllib.request.Request(url, headers={"User-Agent": "rootfs-builder"})
        try:
            with urllib.request.urlopen(req):
                # 1.0.0 exists, so bump patch
                print(f"{maj}.{min_v}.{pat + 1}")
        except Exception:
            # 1.0.0 does not exist yet
            print("1.0.0")
