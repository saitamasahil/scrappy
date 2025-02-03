# Use the Ubuntu 20.04 base image for aarch64
FROM arm64v8/ubuntu:20.04

# Set environment variables to avoid interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Define the version as a build argument with a default value
ARG VERSION=3.12.0

# Update the package list and install essential packages including make, g++, gcc, and git
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
  vim \
  sudo \
  p7zip-full \
  software-properties-common \
  libgles2-mesa-dev \
  libgl1-mesa-dev && \
  apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy the Qt-5.15.15 folder to the desired Qt install location
COPY Qt-5.15.15 /opt/Qt-5.15.15

# Ensure all files in Qt-5.15.15 have the appropriate permissions
RUN chmod -R +x /opt/Qt-5.15.15/bin

# Set up environment variables for Qt
ENV QT_HOME=/opt/Qt-5.15.15
ENV PATH="$QT_HOME/bin:$PATH"

# Copy the libs folder to the desired location
COPY libs /usr/local/libs

# Update the library cache to include /usr/local/libs
# RUN echo "/usr/local/libs" > /etc/ld.so.conf.d/custom-libs.conf && \
#   ldconfig

# Create the skysource directory
RUN mkdir /skysource

# Download the script to the skysource directory
RUN wget -q -O /skysource/update_skyscraper.sh https://raw.githubusercontent.com/Gemba/skyscraper/master/update_skyscraper.sh && \
  chmod +x /skysource/update_skyscraper.sh

# Replace the LATEST assignment in the update script with the specified version
RUN sed -i "s|LATEST=.*|LATEST=\"${VERSION}\"|" /skysource/update_skyscraper.sh

# Set the entrypoint to run the script on container startup
# ENTRYPOINT ["/skysource/update_skyscraper.sh"]

COPY package_skyscraper.sh /skysource/package_skyscraper.sh
RUN chmod +x /skysource/package_skyscraper.sh
ENTRYPOINT ["/skysource/package_skyscraper.sh"]
