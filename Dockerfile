FROM alpine:3.11

ENV VERSION=4.0.0-beta.3
# Needed for node-gyp otherwise looking for Python2
ENV PYTHON=/usr/bin/python3

# Added busybox-static for easy usage in scratch images
# See https://github.com/nodejs/node/blob/master/BUILDING.md#building-nodejs-on-supported-platforms
RUN apk --no-cache add \
  git \
  busybox-static \
  build-base \
  python3 \
  linux-headers \
  nodejs \
  npm \
  upx

# Copy latest into this image to speedup build
COPY --from=lansible/nexe:latest /root/.nexe /root/.nexe

# Makeflags source: https://math-linux.com/linux/tip-of-the-day/article/speedup-gnu-make-build-and-compilation-process
# Install specified nexe version
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
  npm install --unsafe-perm --global nexe@${VERSION}

# Update internal node-gyp
# https://github.com/nodejs/node-gyp/wiki/Updating-npm%27s-bundled-node-gyp
# Needs npm explore needs bash
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
  apk add --no-cache bash && \
  npm explore npm --global -- npm install node-gyp@latest && \
  apk del bash

# Create dummy app
RUN echo "console.log('hello world')" > index.js

# NOTE(wilmardo): For the upx steps and why --empty see:
# https://github.com/nexe/nexe/issues/366
# https://github.com/nexe/nexe/issues/610#issuecomment-483336855
# --configure is passed to node configure
# --fully-static: build static node binary (will not work for serialport)
# --partly-static: keep support for dynamic linking
# https://github.com/nodejs/node/blob/master/configure.py#L131
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
  nexe --target alpine --build --empty --verbose --configure="--partly-static" --output test && \
  rm -f test

# Get node version to package only the current installed version (copy earlier might have been an old version)
# Remove any other version then the current node version
# Remove all files except the ones needed for nexe build
RUN export NODE_VERSION=$(node --version | sed 's/^v//'); \
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
    -not -name 'configure.py' -delete

# Only run upx when not yet packaged
# grep on stderr and stdout, therefore the redirect
# no upx: 54.6M
# --best: 18.6M
# brute or ultra-brute stops it from working
# upx -t to test binary
RUN if upx -t /root/.nexe/*/out/Release/node 2>&1 | grep -q 'NotPackedException'; then \
    upx --best /root/.nexe/*/out/Release/node; \
  fi && \
  upx -t /root/.nexe/*/out/Release/node
