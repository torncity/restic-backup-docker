#!/bin/sh

IMAGE_TAG="ghcr.io/torncity/restic-backup-docker:stream"

# https://docs.docker.com/build/building/multi-platform/#building-multi-platform-images
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    -t "$IMAGE_TAG" .
