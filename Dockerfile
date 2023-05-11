# Declare args
ARG ALPINE_IMAGE_TAG=3.14
ARG LINKDING_IMAGE_TAG=latest
ARG LITESTREAM_VERSION=v0.3.8

FROM docker.io/alpine:$ALPINE_IMAGE_TAG as builder

# Download the static build of Litestream directly into the path & make it executable.
# This is done in the builder and copied as the chmod doubles the size.
ADD https://github.com/benbjohnson/litestream/releases/download/$LITESTREAM_VERSION/litestream-$LITESTREAM_VERSION-linux-amd64-static.tar.gz /tmp/litestream.tar.gz
RUN tar -C /usr/local/bin -xzf /tmp/litestream.tar.gz

# Pull linkding docker image.
FROM docker.io/sissbruecker/linkding:$LINKDING_IMAGE_TAG

# Copy Litestream from builder.
COPY --from=builder /usr/local/bin/litestream /usr/local/bin/litestream

# Copy Litestream configuration file.
COPY etc/litestream.yml /etc/litestream.yml

# Copy custom uwsgi. This allows to run with 256MB RAM.
COPY uwsgi.ini /etc/linkding/uwsgi.ini

# Copy startup script and make it executable.
COPY scripts/run.sh /scripts/run.sh
RUN chmod +x /scripts/run.sh

# Litestream spawns linkding's webserver as subprocess.
CMD ["/scripts/run.sh"]
