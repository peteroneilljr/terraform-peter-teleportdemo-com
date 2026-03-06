ARG BASE_IMAGE=debian:12
FROM ${BASE_IMAGE}

ARG TELEPORT_VERSION=17.4.7

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl sudo ca-certificates && \
    curl -O https://cdn.teleport.dev/teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    tar xf teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    ./teleport/install && \
    rm -rf teleport teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["teleport", "start"]
