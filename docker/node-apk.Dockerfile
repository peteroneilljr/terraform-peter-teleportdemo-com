FROM alpine:3.21

ARG TELEPORT_VERSION=17.4.7

RUN apk add --no-cache curl sudo gcompat && \
    curl -O https://cdn.teleport.dev/teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    tar xf teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    ./teleport/install && \
    rm -rf teleport teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz

ENTRYPOINT ["teleport", "start"]
