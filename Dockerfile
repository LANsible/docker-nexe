FROM alpine:3.10

# See https://github.com/nodejs/node/blob/master/BUILDING.md#building-nodejs-on-supported-platforms
RUN apk --no-cache add \
  g++ \
  make \
  python \
  linux-headers \
  npm \
  upx

# Makeflags source: https://math-linux.com/linux/tip-of-the-day/article/speedup-gnu-make-build-and-compilation-process
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
  npm install --unsafe-perm --global nexe@4.0.0-beta.3

RUN echo "console.log('hello world')" >> index.js

# NOTE(wilmardo): For the upx steps and why --empty see:
# https://github.com/nexe/nexe/issues/366
# https://github.com/nexe/nexe/issues/610#issuecomment-483336855
RUN nexe --build --empty --no-mangle --verbose --configure="--fully-static"
RUN upx --brute /root/.nexe/*/out/Release/node
