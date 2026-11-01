# Rebuild upstream tagged sources because the legacy public image was removed.
# This is a local-development compatibility image, not a maintained production store.
FROM golang:1.24-bookworm AS build
ARG COMPONENT=minio
ARG RELEASE=RELEASE.2025-04-22T22-12-26Z
RUN git clone --depth 1 --branch ${RELEASE} https://github.com/minio/${COMPONENT}.git /src
WORKDIR /src
RUN CGO_ENABLED=0 go build -trimpath -o /out/tool .
FROM debian:bookworm-slim
# The official Go builder already includes the trust bundle used for its HTTPS
# source fetches. Copy it instead of adding an independent apt mirror download
# to every first-time MinIO/mc build.
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
RUN test -s /etc/ssl/certs/ca-certificates.crt && mkdir /data && chown 1001:1001 /data
ARG COMPONENT=minio
COPY --from=build /out/tool /usr/local/bin/tool
RUN ln -s /usr/local/bin/tool /usr/local/bin/${COMPONENT}
USER 1001:1001
ENV MC_CONFIG_DIR=/tmp/.mc
ENTRYPOINT ["/usr/local/bin/tool"]
