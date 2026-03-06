ARG BASE_IMAGE=rockylinux:9
FROM ${BASE_IMAGE}

ARG TELEPORT_VERSION=17.4.7

RUN dnf install -y --allowerasing sudo curl tar gzip && \
    curl -O https://cdn.teleport.dev/teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    tar xf teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    ./teleport/install && \
    rm -rf teleport teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    dnf clean all

ENTRYPOINT ["teleport", "start"]
