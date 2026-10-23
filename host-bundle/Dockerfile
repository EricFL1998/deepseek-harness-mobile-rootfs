FROM node:24-bookworm-slim
ARG DSH_VERSION=0.2.1-rc.2
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends python3 git ca-certificates && rm -rf /var/lib/apt/lists/*
RUN npm install -g --no-audit --no-fund @deepseek-ai/dsh@${DSH_VERSION} pnpm esbuild
COPY patches /patches
COPY apply-patches.sh /apply-patches.sh
RUN sh /apply-patches.sh
WORKDIR /usr/local/lib/node_modules/@deepseek-ai/dsh/lib
RUN esbuild bin.js --bundle --platform=node --format=esm --target=node24 \
      --outfile=host.bundle.mjs --external:*.node --external:node:* \
      --log-level=warning && ls -lh host.bundle.mjs
