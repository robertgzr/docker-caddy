# vim: ft=dockerfile
ARG CADDY_VERSION=HEAD
ARG BUILD_DATE

FROM docker.io/library/golang:1.12-alpine as build

ENV GO111MODULE=on

# get dependencies
RUN apk add git && \
    go get -u arp242.net/goimport

WORKDIR $GOPATH/src/github.com/mholt/caddy

# checkout CADDY_VERSION
RUN git clone https://github.com/mholt/caddy.git . && \
    git checkout -f $CADDY_VERSION

# FIXME
RUN echo "replace github.com/h2non/gock => gopkg.in/h2non/gock.v1 v1.0.14" >> go.mod

# disable telemetry
RUN sed -i -e 's|var EnableTelemetry.*|var EnableTelemetry = false|' ./caddy/caddymain/run.go

# install caddy 3rd party plugins
COPY plugins.sh /
RUN /plugins.sh ./caddy/caddymain/run.go

ARG GOOS=linux
ARG GOARCH=amd64
ARG GOARM

# set go toolchain env
ENV GOOS=$GOOS \
    GOARCH=$GOARCH \
    GOARM=$GOARM \
    CGO_ENABLED=0

# static build
# https://github.com/golang/go/issues/26492
RUN go build -a \
        -ldflags '-extldflags "-fno-PIC -static"' \
        -tags "osusergo netgo static_build" \
        -o /out/caddy \
        ./caddy

# get certs for deployment
RUN apk add ca-certificates


# put binary and certs into scratch container
FROM scratch

LABEL \
    maintainer="robertgzr <r@gnzler.io>" \
    RUN="podman run --name some-caddy -p 80:2015 -dt IMAGE" \
    org.label-schema.schema-version="1.0" \
    org.label-schema.version=$CADDY_VERSION \
    org.label-schema.build-date=$BUILD_DATE \
    org.label-schema.vcs-url="https://github.com/robertgzr/docker-caddy"

COPY --from=build /out/caddy /bin/caddy
COPY Caddyfile.default /etc/Caddyfile

# add certs from build to enable HTTPS
COPY --from=build \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/ssl/certs/ca-certificates.crt

EXPOSE 2015
WORKDIR /var/www
ENTRYPOINT ["/bin/caddy"]
CMD ["-agree", "-conf", "/etc/Caddyfile"]
