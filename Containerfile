ARG OPENMAXIO_TAG="v1.7.6"
ARG NODE_VERSION="18"
ARG GOLANG_VERSION="1.24"

FROM alpine/git:latest as git

WORKDIR /app

ENV GIT_BRANCH="${OPENMAXIO_TAG}"
RUN git clone -b "${GIT_BRANCH}" --single-branch --depth 1 https://github.com/OpenMaxIO/openmaxio-object-browser

########################################################################################################################
FROM node:${NODE_VERSION} as uilayer

WORKDIR /app

COPY --from=git /app/openmaxio-object-browser/web-app .

RUN corepack enable && corepack prepare
RUN yarn install && yarn build

########################################################################################################################
FROM golang:${GOLANG_VERSION} as golayer

WORKDIR /go/src/github.com/minio/console/

RUN apt-get update -y && apt-get install -y ca-certificates

COPY --from=git /app/openmaxio-object-browser/go.mod go.mod
COPY --from=git /app/openmaxio-object-browser/go.sum go.sum

# Get dependencies - will also be cached if we won't change mod/sum
RUN go mod download

COPY --from=git /app/openmaxio-object-browser .
ENV CGO_ENABLED=0

COPY --from=uilayer /app/build web-app/build
RUN go build --tags=kqueue,operator -ldflags "-w -s" -a -o console ./cmd/console

########################################################################################################################
FROM redhat/ubi9:latest
EXPOSE 9090

COPY --from=golayer /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=golayer /go/src/github.com/minio/console/console .

RUN ./console --version

ENTRYPOINT ["/console"]
CMD ["server"]
