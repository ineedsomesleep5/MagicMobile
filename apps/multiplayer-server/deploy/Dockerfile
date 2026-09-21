# Render can build this file from the repository. Runtime bytes come from one
# immutable GitHub release asset, authenticated by its reviewed SHA-256.
ARG JRE_IMAGE=eclipse-temurin:17-jre-jammy
FROM ${JRE_IMAGE}
ARG RUNTIME_URL
ARG RUNTIME_SHA256
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN case "$RUNTIME_URL" in https://github.com/ineedsomesleep5/MagicMobile/releases/download/*) ;; *) exit 2;; esac \
    && test "${#RUNTIME_SHA256}" -eq 64 \
    && curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 "$RUNTIME_URL" -o /tmp/runtime.tar.gz \
    && printf '%s  %s\n' "$RUNTIME_SHA256" /tmp/runtime.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/runtime.tar.gz -C /app \
    && rm /tmp/runtime.tar.gz \
    && sha256sum -c SHA256SUMS \
    && chown -R 10001:10001 /app
USER 10001:10001
ENV BIND_ADDRESS=0.0.0.0 PORT=10000 MAX_MATCHES=1 \
    JAVA_HEAP_INITIAL=64m JAVA_HEAP_MAX=256m JAVA_PROCESSORS=1
EXPOSE 10000
CMD ["bash", "/app/start.sh"]
