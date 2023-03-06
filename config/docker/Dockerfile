FROM golang:alpine AS builder

WORKDIR $GOPATH/src/github.com/nats-io/nats-server

MAINTAINER Waldemar Quevedo <wally@synadia.com>

RUN apk add --update git

COPY . .

# RUN go mod tidy

RUN CGO_ENABLED=0 go build -v -a -tags netgo -installsuffix netgo -ldflags "-s -w -X github.com/nats-io/nats-server/v2/server.gitCommit=`git rev-parse --short HEAD`" -o /nats-server

FROM alpine:latest

RUN apk add --update ca-certificates && mkdir -p /nats/bin && mkdir /nats/conf

COPY docker/nats-server.conf /nats/conf/nats-server.conf
COPY --from=builder /nats-server /nats/bin/nats-server

# NOTE: For backwards compatibility, we add a symlink to /gnatsd which is
# where the binary from the scratch container image used to be located.
RUN ln -ns /nats/bin/nats-server /bin/nats-server && ln -ns /nats/bin/nats-server /nats-server && ln -ns /nats/bin/nats-server /gnatsd && ln -ns /nats/bin/nats-server /usr/local/bin/nats-server

# Expose client, management, cluster and gateway ports
EXPOSE 4222 8222 6222 7522 7422

ENTRYPOINT ["/bin/nats-server"]
CMD ["-c", "/nats/conf/nats-server.conf"]

