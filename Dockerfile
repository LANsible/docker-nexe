FROM alpine:3.10

ENV VERSION=4.0.0-beta.3

# See https://github.com/nodejs/node/blob/master/BUILDING.md#building-nodejs-on-supported-platforms
RUN apk --no-cache add \
  g++ \
  make \
  python \
  linux-headers \
  npm \
  upx

# Copy latest into this image to speedup build
COPY --from=lansible/nexe:latest /root/.nexe /root/.nexe

# Makeflags source: https://math-linux.com/linux/tip-of-the-day/article/speedup-gnu-make-build-and-compilation-process
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
  npm install --unsafe-perm --global nexe@${VERSION}

RUN echo "console.log('hello world')" >> index.js

# NOTE(wilmardo): For the upx steps and why --empty see:
# https://github.com/nexe/nexe/issues/366
# https://github.com/nexe/nexe/issues/610#issuecomment-483336855
# --configure is passed to node configure
# --fully-static: build static node binary
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
  nexe --build --empty --no-mangle --verbose --configure="--fully-static"

# Only run upx when not yet packaged
# grep on stderr and stdout, therefore the redirect
# no upx: 43.1M
# --best: 14.8M
# brute or ultra-brute stops it from working
RUN if upx -t /root/.nexe/*/out/Release/node 2>&1 | grep -q 'NotPackedException'; then \
      upx --best /root/.nexe/*/out/Release/node; \
    fi

# Test node binary
RUN upx -t /root/.nexe/*/out/Release/node
