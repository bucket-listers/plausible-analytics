#!/usr/bin/env bash
docker buildx create --name buildx-1 --use
docker buildx inspect --bootstrap
docker buildx build --platform linux/amd64,linux/arm64 -t fbscarelbl/plausible-analytics:${1} --push .
