FROM eclipse-temurin:17-jdk-jammy

ARG XMAGE_DOWNLOAD_URL=https://github.com/magefree/mage/releases/download/xmage_1.4.60V1/mage-full_1.4.60-dev_2026-06-20_17-27.zip

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl unzip \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/xmage /opt/magicmobile/classes /opt/magicmobile/src \
  && curl -L --fail --retry 3 --retry-delay 3 -o /tmp/xmage.zip "$XMAGE_DOWNLOAD_URL" \
  && (unzip -q /tmp/xmage.zip -d /opt/xmage || test "$?" = "1") \
  && rm /tmp/xmage.zip

COPY MagicMobileBridge.java /opt/magicmobile/src/MagicMobileBridge.java
COPY MagicMobileEmbeddedServerBridge.java /opt/magicmobile/src/MagicMobileEmbeddedServerBridge.java
COPY start.sh /opt/magicmobile/start.sh

RUN javac \
    -cp "/opt/xmage/xmage/mage-client/lib/*:/opt/xmage/xmage/mage-client/plugins/*:/opt/xmage/xmage/mage-server/lib/*:/opt/xmage/xmage/mage-server/plugins/*" \
    -d /opt/magicmobile/classes \
    /opt/magicmobile/src/MagicMobileBridge.java \
    /opt/magicmobile/src/MagicMobileEmbeddedServerBridge.java \
  && chmod +x /opt/magicmobile/start.sh

ENV XMAGE_HOME=/opt/xmage/xmage \
  XMAGE_HOST=127.0.0.1 \
  XMAGE_PORT=17171 \
  BRIDGE_PORT=17172 \
  XMAGE_EMBEDDED_BRIDGE=true \
  XMAGE_SERVER_XMX=1024m

EXPOSE 17171 17172 17179

CMD ["/opt/magicmobile/start.sh"]
