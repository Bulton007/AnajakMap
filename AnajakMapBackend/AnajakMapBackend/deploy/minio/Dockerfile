# Rebuild upstream tagged sources because the legacy public image was removed.
# This is a local-development compatibility image, not a maintained production store.
FROM golang:1.24-bookworm AS build
ARG COMPONENT=minio
ARG RELEASE=RELEASE.2025-04-22T22-12-26Z
RUN git clone --depth 1 --branch ${RELEASE} https://github.com/minio/${COMPONENT}.git /src
WORKDIR /src
RUN CGO_ENABLED=0 go build -trimpath -o /out/tool .
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/* && mkdir /data && chown 1001:1001 /data
ARG COMPONENT=minio
COPY --from=build /out/tool /usr/local/bin/tool
RUN ln -s /usr/local/bin/tool /usr/local/bin/${COMPONENT}
USER 1001:1001
ENV MC_CONFIG_DIR=/tmp/.mc
ENTRYPOINT ["/usr/local/bin/tool"]
