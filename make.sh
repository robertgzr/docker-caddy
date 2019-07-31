#!/bin/sh

set -e
[ -n "$DEBUG" ] && set -x

REPO=${REPO:-"docker.io/robertgzr/caddy"}
ARCHS=${ARCHS:-"amd64 armv7hf aarch64"}
VERSION=${VERSION:-"v1.0.1"}
DOCKERFILE=${DOCKERFILE:-"Dockerfile"}
OS=${OS:-"linux"}

_info() {
    echo -e "\033[1;34m" "> $1" "\033[0m"
}
_do() {
    echo $@
    [ -n "$DRY" ] && return
    eval $@
}

_build() {
    arch="$1"
    tag="${REPO}:${VERSION}-${arch}"
    build_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    trap '{ rm -f ./latest_image ./latest_container; }' EXIT

    _info "[${arch}] building container image"
    _do buildah bud \
	--file=${DOCKERFILE} \
	--tag=${tag} \
	--build-arg BUILD_DATE=${build_date} \
	--build-arg VERSION=${VERSION} \
	--build-arg GOOS=${GOOS} \
	--build-arg GOARCH=${GOARCH} \
	--build-arg GOARM=${GOARM} \
	--iidfile ./latest_image \
	.

    _info "[${arch}] tagging latest image"
    _do buildah tag ${tag} "${REPO}:latest-${arch}"

    _info "[${arch}] extracting binary"
    buildah from --cidfile ./latest_container `cat ./latest_image`
    cid=`cat ./latest_container`
    mountpath=`buildah mount ${cid}`
    install -Dm0755 ${mountpath}/usr/bin/caddy ./output/caddy-${VERSION}-${arch}
    buildah umount ${cid}
}

_check_and_download_manifest_tool() {
    mt_url="https://github.com/estesp/manifest-tool/releases/download/v0.9.0/manifest-tool-linux-amd64"
    _info "checking if manifest-tool is available"
    which manifest-tool && return
    _info "installing manifest-tool"
    _do curl -sSfL "${mt_url}" -o ./manifest-tool
    chmod u+x ./manifest-tool
}

_push() {
    arch="$1"
    tag_version="${REPO}:${VERSION}-${arch}"
    _info "[${arch}] pushing container images"
    _do buildah push ${tag_version}
    tag_latest="${REPO}:latest-${arch}"
    _do buildah push ${tag_latest}
}

while test $# -gt 0; do
    case "$1" in
	build)
	    export GOOS=${OS}
	    for arch in ${2:-$ARCHS}; do
		unset GOARCH; unset GOARM;
		case "$arch" in
		    amd64)   export GOARCH="amd64" ;;
		    armv7hf) export GOARCH="arm"; export GOARM="7" ;;
		    aarch64) export GOARCH="arm64" ;;
		    *) 	echo "not one of: $ARCHS"
			exit 1 ;;
		esac
		_build $arch
	    done
	    ;;

	push)
	    _check_and_download_manifest_tool
	    for arch in ${2:-$ARCHS}; do
		_push $arch
	    done
	    for ver in ${VERSION} latest; do
		_info "pushing manifest for ${ver}"
		trap "{ rm -f spec-${ver}.yml; }" EXIT
		sed \
			-e "s|{%VERSION%}|${ver}|g" \
			-e "s|{%REPO%}|${REPO}|g" \
			spec.template.yml > spec-${ver}.yml
		_do ./manifest-tool --username=${DOCKER_USERNAME} --password=${DOCKER_PASSWORD} push from-spec ./spec-${ver}.yml
	    done
	    ;;

	webhook)
	    _info "triggering microbadger refresh"
	    curl -X POST ${MB_WEBHOOK}
	    ;;

	upload)
	    _info "uploading artifacts"
	    ls -la ./output/
	    ;;

	-h|--help|help)
	    echo "usage: make.sh <command>"
	    echo ""
	    echo " build"
	    echo " push"
	    echo " webhook"
	    echo " upload"
	    echo ""
	    ;;
    esac
    shift
done
