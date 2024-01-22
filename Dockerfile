FROM lansible/nexe:latest as nexe

# https://hub.docker.com/_/node
FROM node:20.10-alpine3.19
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# https://www.npmjs.com/package/nexe
ENV VERSION=5.0.0-beta.1

# See https://github.com/nodejs/node/blob/master/BUILDING.md#building-nodejs-on-supported-platforms
# git, upx and gcompat(hugo) for downstream image ease of use
RUN apk --no-cache add \
  build-base \
  python3 \
  linux-headers \
  mold \
  upx \
  git \
  gcompat

# Makeflags source: https://math-linux.com/linux/tip-of-the-day/article/speedup-gnu-make-build-and-compilation-process
# Install specified nexe version
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES} CFLAGS=-fuse-ld=mold"; \
  corepack enable && \
  yarn global add --prefix /usr/local nexe@${VERSION}

# Copy compiled NodeJS of previous version, if the version is same the next build is skipped
# Use a copy and not a mounted cache, mounted cache does not persist and is merely a cache
COPY --from=nexe /root/.nexe /root/.nexe

# NOTE(wilmardo): Single layer to avoid needing to recompile node when upx/find fails
# NOTE(wilmardo): For the upx steps and why --empty see:
# https://github.com/nexe/nexe/issues/366
# https://github.com/nexe/nexe/issues/610#issuecomment-483336855
# --configure is passed to node configure
# --fully-static: build static node binary (will not work for serialport)
# --partly-static: keep support for dynamic linking
# https://github.com/nodejs/node/blob/master/configure.py#L131
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES} CFLAGS=-fuse-ld=mold"; \
  echo "console.log('hello world')" > index.js && \
  nexe --build --empty --verbose --configure="--partly-static" --output test && \
  rm -f test index.js

# Get node version to keep only the current installed version (copy earlier might have been an old version)
# Remove any other version then the current node version
# Remove all files except the ones needed for nexe build
#
# Only run upx when not yet packaged
# grep on stderr and stdout, therefore the redirect
# no upx: 54.6M
# --best: 18.6M
# brute or ultra-brute stops it from working
# upx -t to test binary
RUN NODE_VERSION=$(node --version | sed 's/^v//'); \
  find /root/.nexe \
    -type d \
    -not -path /root/.nexe \
    -not -path /root/.nexe/${NODE_VERSION} \
    -maxdepth 1 \
    -exec rm -rf {} +; \
  find /root/.nexe/${NODE_VERSION} \
    -type f \
    -not -name 'node' \
    -not -name '_third_party_main.js' \
    -not -name 'configure.py' -delete; \
  \
  if (upx -t /root/.nexe/*/out/Release/node 2>&1 || true) | grep -q 'NotPackedException'; then \
    upx --best /root/.nexe/*/out/Release/node; \
    upx -t /root/.nexe/*/out/Release/node; \
  fi
