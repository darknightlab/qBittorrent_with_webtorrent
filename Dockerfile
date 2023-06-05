FROM ubuntu:latest as builder

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
    apt install -y wget curl && \
    apt install -y git build-essential pkg-config cmake ninja-build libboost-dev libssl-dev libgeoip-dev zlib1g-dev libgl1-mesa-dev && \
    # install qt5
    # apt install -y qtbase5-dev qttools5-dev libqt5svg5-dev && \
    # install qt6
    apt install -y qt6-base-dev qt6-tools-dev libqt6svg6-dev qt6-l10n-tools qt6-tools-dev-tools && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# build libtorrent
RUN \
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
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
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
    cmake -B build \
    -G Ninja \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DGUI=OFF \
    -DQT6=ON && \
    cmake --build build -j$(nproc) && \
    cmake --install build

RUN \
    ldd /usr/bin/qbittorrent-nox | sort -f

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

FROM builder as gatherer
RUN \
    mkdir /gathered && \
    ldd /usr/bin/qbittorrent-nox | grep "=> /" | awk '{print $3}' |  xargs -I '{}' sh -c "cp -v --parents {} /gathered" && \
    cp --parents /usr/bin/qbittorrent-nox /gathered

FROM ubuntu:latest

COPY --from=gatherer /gathered/usr /usr
COPY --from=gatherer /gathered/lib /usr/lib
COPY --from=builder /sbom.txt /sbom.txt

# to solve qbittorrent(libtorrent)  Non-ASCII characters in directories are handled as dots  https://github.com/qbittorrent/qBittorrent/issues/16127
ENV LC_ALL=C.UTF-8

RUN \
    apt update && \
    apt install -y --no-install-recommends qt6-base-dev qt6-gtk-platformtheme \
    # libqt6sql6 可以不装，没区别
    libqt6sql6 \
    doas && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "permit nopass keepenv :root" >> /etc/doas.conf && \
    chmod 400 /etc/doas.conf

RUN useradd -M -s /bin/bash -U -u 1000 qbtUser

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]