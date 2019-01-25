VERSION:=v0.11.2

all: push

build:
	env CADDY_VERSION=$(VERSION) .travis/build.sh

push: build
	env CADDY_VERSION=$(VERSION) .travis/push.sh

.PHONY: build push