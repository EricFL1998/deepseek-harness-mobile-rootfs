# DeepSeek Harness Mobile Rootfs Builder

Automated multi-architecture Debian 12 rootfs builder for [deepseek-harness-mobile](https://github.com/EricFL1998/deepseek-harness-mobile).

Produces minimal deterministic rootfs images (`rootfs-x86_64.bin` and `rootfs-arm64-v8a.bin`) containing:
- Debian 12 (Bookworm) Slim
- Node.js 24 + pnpm
- Python 3 + Git
- `@deepseek-ai/dsh` with `--profile web` plugins pre-installed

## GitHub Action Workflow

This repository runs GitHub Actions to:
1. Detect upstream `@deepseek-ai/dsh` releases or trigger on manual dispatch.
2. Build multi-arch images (`linux/amd64` and `linux/arm64`) using Docker and QEMU.
3. Export rootfs and compress using deterministic Gzip (`mtime=0`, level 6).
4. Compute SHA-256 and publish GitHub Releases with assets.
5. Generate `rootfs-manifest-fragment.json` for easy synchronization with the Android app.
