FROM archlinux:latest

ARG TELEPORT_VERSION=17.4.7

RUN pacman --disable-sandbox -Syu --noconfirm sudo curl && \
    curl -O https://cdn.teleport.dev/teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    tar xf teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    ./teleport/install && \
    rm -rf teleport teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    pacman -Scc --noconfirm

ENTRYPOINT ["teleport", "start"]
