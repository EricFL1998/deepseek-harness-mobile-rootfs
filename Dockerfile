ARG DSH_VERSION=0.2.1-rc.2
FROM node:24-bookworm-slim

ARG DSH_VERSION
ENV DEBIAN_FRONTEND=noninteractive
ENV PNPM_HOME=/usr/local
ENV PATH=$PNPM_HOME/bin:$PATH

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

# 3. Validation
RUN node /usr/local/lib/node_modules/@deepseek-ai/dsh/lib/bin.js --version
