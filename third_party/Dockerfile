FROM ubuntu:22.04

# Install build dependencies
RUN apt-get update && apt-get install -y \
  cmake \
  build-essential \
  git \
  && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy source
COPY . .

# Run build script
WORKDIR /app/third_party
RUN ls -la && chmod +x ./build_linux.sh && ./build_linux.sh cpu

