FROM debian:12

ARG TELEPORT_VERSION=17.4.7

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl sudo ca-certificates build-essential libncurses-dev git && \
    git clone --depth 1 https://github.com/kragen/myman.git /tmp/myman && \
    cd /tmp/myman && ./configure --disable-variants && make -j$(nproc) && make install && \
    cd / && rm -rf /tmp/myman && \
    echo '[ -t 0 ] && exec myman -z big' >> /root/.profile && \
    curl -O https://cdn.teleport.dev/teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    tar xf teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    ./teleport/install && \
    rm -rf teleport teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz && \
    apt-get purge -y build-essential libncurses-dev git && apt-get autoremove -y && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["teleport", "start"]
