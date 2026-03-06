ARG BASE_IMAGE=opensuse/leap:16.0
FROM ${BASE_IMAGE}

ARG TELEPORT_VERSION=17.4.7

RUN zypper --non-interactive install -y curl sudo tar gzip && \
    curl -O https://cdn.teleport.dev/teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    tar xf teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    ./teleport/install && \
    rm -rf teleport teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    zypper clean --all

ENTRYPOINT ["teleport", "start"]
