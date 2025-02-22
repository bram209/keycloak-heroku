FROM alpine:3.10 as kc

# Copy from https://github.com/jboss-dockerfiles/keycloak/blob/6.0.1/server/Dockerfile
ENV KEYCLOAK_VERSION 6.0.1
ARG KEYCLOAK_DIST=https://downloads.jboss.org/keycloak/$KEYCLOAK_VERSION/keycloak-$KEYCLOAK_VERSION.tar.gz

RUN apk add --no-cache --virtual .build-deps curl \
    && mkdir -p /opt/jboss \
    && cd /opt/jboss/ \
    && curl -L $KEYCLOAK_DIST | tar zx \
    && mv /opt/jboss/keycloak-?.?.?* /opt/jboss/keycloak \
    && apk del --purge .build-deps

FROM adoptopenjdk/openjdk12-openj9:x86_64-alpine-jdk-12.0.1_12_openj9-0.14.1 as jlink-package

# https://gist.github.com/thomasdarimont/94ab3eb748742d2e793f4f5d32e05932
# +openj9.sharedclasses
RUN jlink \
  --no-header-files \
  --no-man-pages \
  --compress=2 \
  --strip-debug \
  --vm=server \
  --exclude-files="**/bin/rmiregistry,**/bin/jrunscript,**/bin/rmid" \
  --add-modules java.base,java.instrument,java.logging,java.management,java.naming,java.scripting,java.se,java.security.jgss,java.security.sasl,java.sql,java.transaction.xa,java.xml,java.xml.crypto,jdk.security.auth,jdk.xml.dom,jdk.unsupported,openj9.sharedclasses \
  --output /opt/java-runtime

FROM alpine:3.10

# Copy from https://github.com/AdoptOpenJDK/openjdk-docker/blob/master/12/jdk/alpine/Dockerfile.openj9.releases.slim
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

RUN apk add --no-cache --virtual .build-deps curl binutils \
    && GLIBC_VER="2.29-r0" \
    && ALPINE_GLIBC_REPO="https://github.com/sgerrand/alpine-pkg-glibc/releases/download" \
    && GCC_LIBS_URL="https://archive.archlinux.org/packages/g/gcc-libs/gcc-libs-8.2.1%2B20180831-1-x86_64.pkg.tar.xz" \
    && GCC_LIBS_SHA256=e4b39fb1f5957c5aab5c2ce0c46e03d30426f3b94b9992b009d417ff2d56af4d \
    && ZLIB_URL="https://archive.archlinux.org/packages/z/zlib/zlib-1%3A1.2.11-3-x86_64.pkg.tar.xz" \
    && ZLIB_SHA256=17aede0b9f8baa789c5aa3f358fbf8c68a5f1228c5e6cba1a5dd34102ef4d4e5 \
    && curl -LfsS https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub -o /etc/apk/keys/sgerrand.rsa.pub \
    && SGERRAND_RSA_SHA256="823b54589c93b02497f1ba4dc622eaef9c813e6b0f0ebbb2f771e32adf9f4ef2" \
    && echo "${SGERRAND_RSA_SHA256} */etc/apk/keys/sgerrand.rsa.pub" | sha256sum -c - \
    && curl -LfsS ${ALPINE_GLIBC_REPO}/${GLIBC_VER}/glibc-${GLIBC_VER}.apk > /tmp/glibc-${GLIBC_VER}.apk \
    && apk add /tmp/glibc-${GLIBC_VER}.apk \
    && curl -LfsS ${ALPINE_GLIBC_REPO}/${GLIBC_VER}/glibc-bin-${GLIBC_VER}.apk > /tmp/glibc-bin-${GLIBC_VER}.apk \
    && apk add /tmp/glibc-bin-${GLIBC_VER}.apk \
    && curl -Ls ${ALPINE_GLIBC_REPO}/${GLIBC_VER}/glibc-i18n-${GLIBC_VER}.apk > /tmp/glibc-i18n-${GLIBC_VER}.apk \
    && apk add /tmp/glibc-i18n-${GLIBC_VER}.apk \
    && /usr/glibc-compat/bin/localedef --force --inputfile POSIX --charmap UTF-8 "$LANG" || true \
    && echo "export LANG=$LANG" > /etc/profile.d/locale.sh \
    && curl -LfsS ${GCC_LIBS_URL} -o /tmp/gcc-libs.tar.xz \
    && echo "${GCC_LIBS_SHA256} */tmp/gcc-libs.tar.xz" | sha256sum -c - \
    && mkdir /tmp/gcc \
    && tar -xf /tmp/gcc-libs.tar.xz -C /tmp/gcc \
    && mv /tmp/gcc/usr/lib/libgcc* /tmp/gcc/usr/lib/libstdc++* /usr/glibc-compat/lib \
    && strip /usr/glibc-compat/lib/libgcc_s.so.* /usr/glibc-compat/lib/libstdc++.so* \
    && curl -LfsS ${ZLIB_URL} -o /tmp/libz.tar.xz \
    && echo "${ZLIB_SHA256} */tmp/libz.tar.xz" | sha256sum -c - \
    && mkdir /tmp/libz \
    && tar -xf /tmp/libz.tar.xz -C /tmp/libz \
    && mv /tmp/libz/usr/lib/libz.so* /usr/glibc-compat/lib \
    && apk del --purge .build-deps glibc-i18n \
    && rm -rf /tmp/*.apk /tmp/gcc /tmp/gcc-libs.tar.xz /tmp/libz /tmp/libz.tar.xz /var/cache/apk/*

ENV JAVA_TOOL_OPTIONS="-XX:+IgnoreUnrecognizedVMOptions -XX:+UseContainerSupport -XX:+IdleTuningCompactOnIdle -XX:+IdleTuningGcOnIdle"

ENV JAVA_HOME=/opt/java-runtime
ENV PATH="$PATH:$JAVA_HOME/bin"

COPY --from=jlink-package /opt/java-runtime /opt/java-runtime


COPY --from=kc --chown=1000:1000 /opt/jboss /opt/jboss

ENV JBOSS_HOME /opt/jboss/keycloak
ENV PROXY_ADDRESS_FORWARDING false

ENV JAVA_TOOL_OPTIONS="-XX:+IgnoreUnrecognizedVMOptions -XX:+UseContainerSupport -XX:+IdleTuningCompactOnIdle -XX:+IdleTuningGcOnIdle -Xquickstart"

EXPOSE 8080
EXPOSE 8443

USER 1000

COPY docker-entrypoint.sh /opt/jboss/tools

RUN /bin/sh -c '/opt/jboss/keycloak/bin/standalone.sh &' ; sleep 60 ; ps aux | grep java | grep -v grep | awk '{print $1}' | xargs kill -1

ENTRYPOINT [ "/opt/jboss/keycloak/bin/standalone.sh" ]
CMD ["-b", "0.0.0.0"]
