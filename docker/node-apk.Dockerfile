FROM debian:12-slim AS stub-builder
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && \
    echo 'int __res_init(void) { return 0; }' > /tmp/stub.c && \
    gcc -shared -o /tmp/libresolv.so.2 /tmp/stub.c

FROM alpine:3.21

ARG TELEPORT_VERSION=17.4.7

RUN apk add --no-cache curl sudo gcompat libgcc && \
    curl -O https://cdn.teleport.dev/teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    tar xf teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    ./teleport/install && \
    rm -rf teleport teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz

# Override gcompat's libresolv.so.2 symlink with a stub providing __res_init
COPY --from=stub-builder /tmp/libresolv.so.2 /lib/

ENTRYPOINT ["teleport", "start"]
