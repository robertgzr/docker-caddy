#!/bin/bash

B=
if [[ `command -v buildah` ]]; then
    B="buildah"
else
    echo "buildah not found, trying docker..."
    if command -v docker; then
        B="docker"
    else
        echo "docker not found, then this won't work..."
        exit 1
    fi
fi

MANIFEST_TOOL_VERSION='v0.9.0'
curl -sSfL https://github.com/estesp/manifest-tool/releases/download/$MANIFEST_TOOL_VERSION/manifest-tool-linux-amd64 \
    -o manifest-tool
chmod +x ./manifest-tool

manifest_push() {
    local version=$2
    local ref=$1:$version

    $B push $ref-amd64
    $B push $ref-armv7hf

    # can't use docker native manifest command
    # docker manifest create --amend $1 $1-amd64 $1-armv7hf
    # docker manifest annotate $1 $1-armv7hf --os linux --arch arm --variant v7
    # docker manifest push $1

    # process and push spec
    sed -e "s|%%VERSION%%|$version|g" spec.template.yml > spec.yml
    ./manifest-tool push from-spec ./spec.yml
    rm spec.yml
}

echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin

BASE=docker.io/$DOCKER_USERNAME/caddy
# push versioned img
manifest_push $BASE $CADDY_VERSION

# tag/push latest img
$B tag $BASE:$CADDY_VERSION-amd64 $BASE:latest-amd64
$B tag $BASE:$CADDY_VERSION-armv7hf $BASE:latest-armv7hf
manifest_push $BASE latest
