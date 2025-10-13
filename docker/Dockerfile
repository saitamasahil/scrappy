FROM docker.io/arm64v8/ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# Skyscraper version to build
ARG VERSION=3.12.0

# Toolchain and runtime deps (Qt5, OpenSSL 1.1, etc.)
RUN apt-get update && \
  apt-get install -y \
  build-essential \
  pkg-config \
  zlib1g-dev \
  libpng-dev \
  libsdl2-dev \
  make \
  g++ \
  gcc \
  git \
  curl \
  wget \
  p7zip-full \
  libgles2-mesa-dev \
  libgl1-mesa-dev \
  # Qt5 toolchain
  qtbase5-dev \
  qtbase5-dev-tools \
  qt5-qmake \
  # OpenSSL 1.1 for Ubuntu 20.04
  libssl-dev \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Working dir
RUN mkdir -p /skysource

# Fetch upstream Skyscraper updater and pin version
RUN wget -q -O /skysource/update_skyscraper.sh https://raw.githubusercontent.com/Gemba/skyscraper/master/update_skyscraper.sh && \
  chmod +x /skysource/update_skyscraper.sh && \
  sed -i "s|LATEST=.*|LATEST=\"${VERSION}\"|" /skysource/update_skyscraper.sh && \
  sed -i 's/sudo \+//g' /skysource/update_skyscraper.sh

# Packaging script
COPY package_skyscraper.sh /skysource/package_skyscraper.sh
RUN chmod +x /skysource/package_skyscraper.sh

ENTRYPOINT ["/skysource/package_skyscraper.sh"]
