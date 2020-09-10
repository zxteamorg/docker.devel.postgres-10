ARG BUILD_IMAGE=alpine:3.8

FROM ${BUILD_IMAGE} AS Builder
RUN apk add --no-cache postgresql
RUN apk add --no-cache bash
COPY docker-build.sql /build-toolkit/
COPY docker-build.sh /build-toolkit/
RUN chmod +x /build-toolkit/docker-build.sh && /build-toolkit/docker-build.sh
COPY docker-entrypoint.sh /build/usr/local/bin/
RUN chmod +x /build/usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["/bin/bash"]

FROM ${BUILD_IMAGE}
RUN apk add --no-cache postgresql
COPY --from=Builder /build/ /
USER root
VOLUME /data
EXPOSE 5432
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
