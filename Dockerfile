FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive 

ARG QBT_VERSION
ARG LIBBT_CMAKE_FLAGS="-Dwebtorrent=ON"
ARG LIBBT_VERSION

WORKDIR /app

# check environment variables
RUN \
    if [ -z "${QBT_VERSION}" ]; then \
    echo 'Missing QBT_VERSION variable. Check your command line arguments.' && \
    exit 1 ; \
    fi ; \
    if [ -z "${LIBBT_VERSION}" ]; then \
    echo 'Missing LIBBT_VERSION variable. Check your command line arguments.' && \
    exit 1 ; \
    fi ;

# install dependencies
RUN \
    apt update && \
    apt install -y build-essential pkg-config automake libtool git zlib1g-dev libssl-dev libgeoip-dev && \
    apt install -y libboost-dev libboost-system-dev libboost-chrono-dev libboost-random-dev && \
    apt install -y qtbase5-dev qttools5-dev libqt5svg5-dev && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# build libtorrent
RUN \
    apt update && \
    apt install -y cmake wget && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    if [ "${LIBBT_VERSION}" = "devel" ]; then \
    git clone \
    --depth 1 \
    --recurse-submodules \
    https://github.com/arvidn/libtorrent.git && \
    cd libtorrent ; \
    elif [ "${LIBBT_VERSION}" = "master" ]; then \
    git clone \
    --depth 1 \
    --recurse-submodules \
    -b master \
    https://github.com/arvidn/libtorrent.git && \
    cd libtorrent ; \
    else \
    wget "https://github.com/arvidn/libtorrent/releases/download/v${LIBBT_VERSION}/libtorrent-rasterbar-${LIBBT_VERSION}.tar.gz" && \
    tar -xf "libtorrent-rasterbar-${LIBBT_VERSION}.tar.gz" && \
    cd "libtorrent-rasterbar-${LIBBT_VERSION}" ; \
    fi && \
    cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_INSTALL_PREFIX=/usr \
    $LIBBT_CMAKE_FLAGS && \
    cmake --build build -j$(nproc) && \
    cmake --install build

# build qbittorrent
RUN \
    if [ "${QBT_VERSION}" = "devel" ]; then \
    git clone \
    --depth 1 \
    --recurse-submodules \
    https://github.com/qbittorrent/qBittorrent.git && \
    cd qBittorrent ; \
    else \
    wget "https://github.com/qbittorrent/qBittorrent/archive/refs/tags/release-${QBT_VERSION}.tar.gz" && \
    tar -xf "release-${QBT_VERSION}.tar.gz" && \
    cd "qBittorrent-release-${QBT_VERSION}" ; \
    fi && \
    ./configure CXXFLAGS="-std=c++17" --disable-gui && \
    make -j$(nproc) && \
    make install

RUN \
    ldd /usr/local/bin/qbittorrent-nox | sort -f

# record compile-time Software Bill of Materials (sbom)
RUN \
    printf "Software Bill of Materials for building qbittorrent-nox\n\n" >> /sbom.txt && \
    if [ "${LIBBT_VERSION}" = "devel" ]; then \
    cd libtorrent && \
    echo "libtorrent-rasterbar git $(git rev-parse HEAD)" >> /sbom.txt && \
    cd .. ; \
    elif [ "${LIBBT_VERSION}" = "master" ]; then \
    cd libtorrent && \
    echo "libtorrent-rasterbar git $(git rev-parse HEAD)" >> /sbom.txt && \
    cd .. ; \
    else \
    echo "libtorrent-rasterbar ${LIBBT_VERSION}" >> /sbom.txt ; \
    fi && \
    if [ "${QBT_VERSION}" = "devel" ]; then \
    cd qBittorrent && \
    echo "qBittorrent git $(git rev-parse HEAD)" >> /sbom.txt && \
    cd .. ; \
    else \
    echo "qBittorrent ${QBT_VERSION}" >> /sbom.txt ; \
    fi && \
    echo >> /sbom.txt && \
    cat /sbom.txt

RUN \
    apt update && \
    apt install -y doas && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "permit nopass keepenv :root" >> /etc/doas.conf && \
    chmod 400 /etc/doas.conf

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]