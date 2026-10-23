#!/usr/bin/env python3
import gzip
import hashlib
import json
import os
import shutil
import sys

def compress_tar(src_tar: str, dst_bin: str) -> tuple[str, int]:
    print(f"Compressing {src_tar} -> {dst_bin} with mtime=0, level=6...")
    with open(src_tar, "rb") as fi, gzip.GzipFile(dst_bin, "wb", compresslevel=6, mtime=0) as fo:
        shutil.copyfileobj(fi, fo, 1024 * 1024)
    
    sha256 = hashlib.sha256()
    size = os.path.getsize(dst_bin)
    with open(dst_bin, "rb") as f:
        while chunk := f.read(1024 * 1024):
            sha256.update(chunk)
            
    digest = sha256.hexdigest().upper()
    print(f"Done: {dst_bin}")
    print(f"  SHA256: {digest}")
    print(f"  Size:   {size} bytes ({size / (1024*1024):.2f} MB)")
    return digest, size

def main():
    if len(sys.argv) < 5:
        print("Usage: package_rootfs.py <dsh_version> <rootfs_version> <bridge_version> "
              "<x86_tar> <arm64_tar> [output_dir]")
        sys.exit(1)

    dsh_version = sys.argv[1]
    rootfs_version = sys.argv[2]
    bridge_version = sys.argv[3]
    x86_tar = sys.argv[4]
    arm64_tar = sys.argv[5]
    out_dir = sys.argv[6] if len(sys.argv) > 6 else "dist"

    os.makedirs(out_dir, exist_ok=True)
    x86_bin = os.path.join(out_dir, "rootfs-x86_64.bin")
    arm64_bin = os.path.join(out_dir, "rootfs-arm64-v8a.bin")

    x86_sha, x86_size = compress_tar(x86_tar, x86_bin)
    arm64_sha, arm64_size = compress_tar(arm64_tar, arm64_bin)

    # Three segments, one meaning each. The Android client splits this string to
    # decide what kind of update it is looking at:
    #   - rootfs or dsh segment moved   -> the image must be re-downloaded
    #   - only the bridge segment moved -> the plugin can be upgraded in place,
    #     so the image update stays optional
    runtime_version = f"{rootfs_version}-dsh{dsh_version}-bridge{bridge_version}"

    manifest_fragment = {
        "rootfsName": "dsh-rootfs",
        "runtimeVersion": runtime_version,
        "releaseTag": f"rootfs-v{rootfs_version}",
        "bridgeVersion": bridge_version,
        "baseDistro": "debian-12-slim",
        "libc": "glibc",
        "pageSize": "16k-compatible",
        "archiveFormat": "tar.gz",
        "bundledPackages": [
            "node-24",
            "pnpm",
            f"@deepseek-ai/dsh@{dsh_version}",
            f"dsh-mobile-bridge-plugin@{bridge_version}",
            "python3",
            "git"
        ],
        "downloadUrls": {
            "x86_64": f"https://github.com/EricFL1998/deepseek-harness-mobile-rootfs/releases/download/rootfs-v{rootfs_version}/rootfs-x86_64.bin",
            "arm64-v8a": f"https://github.com/EricFL1998/deepseek-harness-mobile-rootfs/releases/download/rootfs-v{rootfs_version}/rootfs-arm64-v8a.bin"
        },
        "downloadSha256": {
            "x86_64": x86_sha,
            "arm64-v8a": arm64_sha
        },
        "archiveSizeBytes": x86_size,
        "prootLibrary": "libproot.so",
        # The image was built from the resolved DSH version and the Android
        # patches were applied to its package files. Clients can accept any DSH
        # segment and must skip their own version-pinned full-file patches.
        "androidPatched": True,
        "androidPatchRevision": 1
    }

    manifest_path = os.path.join(out_dir, "rootfs-manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest_fragment, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Generated manifest: {manifest_path}")

if __name__ == "__main__":
    main()
