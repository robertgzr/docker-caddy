# vim: ft=dockerfile
ARG CADDY_VERSION=HEAD

FROM docker.io/library/golang:1.11-alpine as build

# get dependencies
RUN apk add git && \
    go get -u arp242.net/goimport

# get sources
RUN go get -d github.com/mholt/caddy/caddy && \
    go get -d github.com/caddyserver/builds

# checkout version?
ENV CADDY_VERSION=$CADDY_VERSION
WORKDIR $GOPATH/src/github.com/mholt/caddy
RUN git checkout -f $CADDY_VERSION

# disable telemetry
WORKDIR $GOPATH/src/github.com/mholt/caddy/caddy/caddymain
RUN sed -i -e 's|var EnableTelemetry.*|var EnableTelemetry = false|' run.go

# install caddy 3rd party plugins
COPY plugins.sh /
RUN /plugins.sh

WORKDIR $GOPATH/src/github.com/mholt/caddy/caddy
# force static build
RUN sed -i -e 's|{"build", "-ldflags", ldflags}|{"build", "-a", "-tags", "netgo", "-ldflags", ldflags + " -w"}|' build.go
RUN go run build.go && \
    install -Dm00755 caddy /out/caddy

# get certs for deployment
RUN apk add ca-certificates

# put binary and certs into scratch container
FROM scratch

COPY --from=build /out/caddy /bin/caddy
COPY Caddyfile.default /etc/Caddyfile

# add certs from build to enable HTTPS
COPY --from=build \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/ssl/certs/ca-certificates.crt

EXPOSE 80 443 2015
WORKDIR /var/www
ENTRYPOINT ["/bin/caddy"]
CMD ["-agree", "-conf", "/etc/Caddyfile"]
