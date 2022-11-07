FROM lansible/mold:1.6.0 as mold
FROM lansible/nexe:latest as nexe
FROM lansible/upx:latest as upx

FROM alpine:3.16
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# https://www.npmjs.com/package/nexe
ENV VERSION=v4.0.0-rc.1
# Needed for node-gyp otherwise looking for Python2
ENV PYTHON=/usr/bin/python3

# See https://github.com/nodejs/node/blob/master/BUILDING.md#building-nodejs-on-supported-platforms
RUN apk --no-cache add \
  git \
  build-base \
  python3 \
  linux-headers \
  nodejs-current

# Setup mold for faster compile
COPY --from=mold /usr/local/bin/mold /usr/local/bin/mold
COPY --from=mold /usr/local/libexec/mold /usr/local/libexec/mold

# Makeflags source: https://math-linux.com/linux/tip-of-the-day/article/speedup-gnu-make-build-and-compilation-process
# Install specified nexe version
# TODO update -B/usr/local/libexec/mold to -fuse-ld=mold when GCC > 12.1.0
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES} CFLAGS=-B/usr/local/libexec/mold"; \
  corepack enable && \
  yarn global add --prefix /usr/local nexe@${VERSION}

# Copy compiled NodeJS of previous version, if the version is same the next build is skipped
COPY --from=nexe /root/.nexe /root/.nexe

# NOTE(wilmardo): For the upx steps and why --empty see:
# https://github.com/nexe/nexe/issues/366
# https://github.com/nexe/nexe/issues/610#issuecomment-483336855
# --configure is passed to node configure
# --fully-static: build static node binary (will not work for serialport)
# --partly-static: keep support for dynamic linking
# https://github.com/nodejs/node/blob/master/configure.py#L131
# TODO update -B/usr/local/libexec/mold to -fuse-ld=mold when GCC > 12.1.0
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES} CFLAGS=-B/usr/local/libexec/mold"; \
  echo "console.log('hello world')" > index.js && \
  nexe --build --empty --verbose --configure="--partly-static" --output test && \
  rm -f test index.js

# Get node version to keep only the current installed version (copy earlier might have been an old version)
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

# 'Install' upx from image since upx isn't available for aarch64 from Alpine
COPY --from=upx /usr/bin/upx /usr/bin/upx
# Only run upx when not yet packaged
# grep on stderr and stdout, therefore the redirect
# no upx: 54.6M
# --best: 18.6M
# brute or ultra-brute stops it from working
# upx -t to test binary
RUN if (upx -t /root/.nexe/*/out/Release/node 2>&1 || true) | grep -q 'NotPackedException'; then \
    upx --best /root/.nexe/*/out/Release/node; \
  fi && \
  upx -t /root/.nexe/*/out/Release/node
