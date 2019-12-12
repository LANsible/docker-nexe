# docker-nexe

Compile Node just once instead of each build. Use it like:

```Dockerfile
COPY --from=lansible/nexe-cache:latest /root/.nexe/ /root/.nexe/
RUN nexe \
    --build \
    --output zigbee2mqtt
```

With expiremental enabled:

```Dockerfile
RUN --mount=type=cache,from=lansible/nexe-cache:latest,source=/root/.nexe/,target=/root/.nexe/ \
  nexe \
    --build \
    --output zigbee2mqtt
```
