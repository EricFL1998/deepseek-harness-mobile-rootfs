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

# 5. Validation
RUN node /usr/local/lib/node_modules/@deepseek-ai/dsh/lib/bin.js --version
