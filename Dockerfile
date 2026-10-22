ARG DSH_VERSION=0.2.1-rc.2
ARG BRIDGE_VERSION=1.1.0
FROM node:24-bookworm-slim

ARG DSH_VERSION
ARG BRIDGE_VERSION
ENV DEBIAN_FRONTEND=noninteractive
ENV PNPM_HOME=/usr/local
ENV PATH=$PNPM_HOME/bin:$PATH

# The mobile bridge plugin is installed from its GitHub source tarball, not npm:
# it is not published, and `lib/` is committed there so no build step runs here.
ARG BRIDGE_REPOSITORY=https://github.com/EricFL1998/deepseek-harness-mobile-bridge-plugin

# 1. Install system runtime tools (Python 3, Git, CA certificates)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    git \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man /usr/share/info /usr/share/lintian

# 2. Install pnpm and target @deepseek-ai/dsh
RUN npm install -g --no-audit --no-fund @deepseek-ai/dsh@${DSH_VERSION} pnpm \
  && /opt/dsh/bin/dsh plugin --profile web install \
  || (/usr/local/bin/dsh plugin --profile web install) \
  && npm cache clean --force \
  && rm -rf /root/.npm /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack /usr/local/bin/npm /usr/local/bin/npx \
  && mkdir -p /opt/dsh/bin \
  && printf '#!/bin/sh\nexec /usr/local/bin/dsh "$@"\n' > /opt/dsh/bin/dsh \
  && chmod +x /opt/dsh/bin/dsh

# 3. Install the mobile bridge plugin into the web profile.
#
# New installs ship with the plugin already present, so a fresh device gets the
# compatibility layer without a second network round trip. Existing devices are
# NOT forced to re-download this image when only the plugin moves: the Android
# client upgrades the plugin in place inside the rootfs, and the image is only
# rebuilt for a DSH bump. The version baked here is recorded in the manifest as
# `-bridge<version>`, which is what lets both sides tell the two cases apart.
RUN dsh plugin --profile web add ${BRIDGE_REPOSITORY}#v${BRIDGE_VERSION} \
  && node -e " \
       const fs = require('node:fs'); \
       const path = '/root/.dsh/profiles/web/package.json'; \
       const pkg = JSON.parse(fs.readFileSync(path, 'utf8')); \
       pkg.dsh ??= {}; \
       pkg.dsh.profile ??= {}; \
       const bundles = new Set(pkg.dsh.profile.bundles ?? []); \
       bundles.add('dsh-mobile-bridge-plugin'); \
       pkg.dsh.profile.bundles = [...bundles]; \
       fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + '\n'); \
     "

# 3b. 手机 profile 默认启用官方 workflow（与桌面一致）。
#
# web-app 只带 ptc-runtime；workflow-ptc（引擎）和 tool-workflow（模型工具）
# 是可选行，默认禁用，于是模型没有 workflow 工具。这里写进 profile 的 patch 层，
# 与官方插件页里打开这两个开关等价；客户端的 ensureOfficialWorkflowEnabled()
# 也会对升级上来的旧镜像做同样的幂等调用。
RUN mkdir -p /root/.dsh/profiles/web \
  && node -e " \
       const fs = require('node:fs'); \
       const path = '/root/.dsh/profiles/web/cordis.patch.yml'; \
       const rows = [ \
         '- id: tool-workflow', \
         '  disabled: false', \
         '- id: workflow-ptc', \
         '  disabled: false', \
       ].join('\\n'); \
       const current = fs.existsSync(path) ? fs.readFileSync(path, 'utf8') : ''; \
       if (!current.includes('id: tool-workflow')) { \
         fs.appendFileSync(path, (current.endsWith('\\n') || current === '' ? '' : '\\n') + rows + '\\n'); \
       } \
     " \
  && grep -q 'id: tool-workflow' /root/.dsh/profiles/web/cordis.patch.yml

# 4. Validation: the plugin must resolve and declare its bundle patch, or the
#    image would ship a profile that silently loads no bridge.
RUN node -e " \
      const fs = require('node:fs'); \
      const base = '/root/.dsh/profiles/web/node_modules/dsh-mobile-bridge-plugin'; \
      const pkg = JSON.parse(fs.readFileSync(base + '/package.json', 'utf8')); \
      if (pkg.version !== process.env.BRIDGE_VERSION) { \
        console.error('bridge version mismatch: ' + pkg.version + ' != ' + process.env.BRIDGE_VERSION); \
        process.exit(1); \
      } \
      const patch = pkg.dsh && pkg.dsh.bundle && pkg.dsh.bundle.patch; \
      if (!patch || !fs.existsSync(base + '/' + patch)) { \
        console.error('bridge bundle patch missing: ' + patch); \
        process.exit(1); \
      } \
      if (!fs.existsSync(base + '/' + pkg.main)) { \
        console.error('bridge entry missing: ' + pkg.main); \
        process.exit(1); \
      } \
      console.log('bridge ' + pkg.version + ' installed with patch ' + patch); \
    "
ENV BRIDGE_VERSION=${BRIDGE_VERSION}

# 5. proot/Android 下 libc 探测失败时的平台包兜底
#
# node-addon-require-builtin 在运行时先探测 libc 家族，再按
# `node-addon-require-builtin-linux-<arch>-gnu|musl` 找平台包。proot 里三条
# 探测路径都可能落空：
#   - 读 node 的 ELF PT_INTERP（fs.readSync/pread）会触发 ENOSYS；
#   - /proc/self/maps 映射的是 Android 的 bionic，不是 glibc；
#   - process.report 取不到 glibcVersionRuntime。
# 全部落空后脚本默认按 musl 查找，而 Debian 镜像里装的是 -gnu 包，于是
# Host 启动时报 `Cannot find module .../node-addon-require-builtin/build/...`
# 并以 exit=1 退出。
#
# 镜像本身就是 glibc，把 musl 平台名软链到同一份 gnu 包即可：探测猜错时也能
# 加载正确的二进制，探测正确时这条软链不会被用到。对任意同族包都生效。
#
# 校验：两种平台名都能解析到可用的 ESM loader binding。
RUN set -eux; \
    modules=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules; \
    arch="$(node -p 'process.arch')"; \
    for gnu in "$modules"/*-linux-"$arch"-gnu; do \
      [ -d "$gnu" ] || continue; \
      musl="${gnu%-gnu}-musl"; \
      [ -e "$musl" ] || ln -s "$(basename "$gnu")" "$musl"; \
    done; \
    node -e " \
      const modules = process.argv[1]; \
      for (const suffix of ['gnu', 'musl']) { \
        const name = modules + '/node-addon-require-builtin-linux-' + process.arch + '-' + suffix; \
        const addon = require(name); \
        const loader = addon.requireBuiltin('internal/modules/esm/loader'); \
        if (typeof loader.getOrInitializeCascadedLoader !== 'function') { \
          throw new Error(name + ' returned an unusable ESM loader'); \
        } \
      } \
      console.log('native addon resolves for gnu and musl platform names'); \
    " "$modules"

# 6. Validation
RUN node /usr/local/lib/node_modules/@deepseek-ai/dsh/lib/bin.js --version
