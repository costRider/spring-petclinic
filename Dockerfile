# syntax=docker/dockerfile:1.6

ARG MAVEN_IMAGE=maven:3.9-eclipse-temurin-21
ARG JDK_IMAGE=eclipse-temurin:21-jdk
ARG DISTROLESS_IMAGE=gcr.io/distroless/base-debian12:nonroot

# =========================
# 1) Build
# =========================
FROM ${MAVEN_IMAGE} AS builder
WORKDIR /app

COPY pom.xml ./
RUN --mount=type=cache,target=/root/.m2 \
    mvn -q -DskipTests dependency:go-offline

COPY . .
RUN --mount=type=cache,target=/root/.m2 \
    mvn -q -DskipTests package

RUN cp target/*.jar /app/app.jar

# =========================
# 2) Whatap Agent
# =========================
FROM ${JDK_IMAGE} AS whatap_agent
WORKDIR /whatap

# 🔥 압축 해제 → 폴더 그대로 사용
COPY whatap/whatap.agent.java.tar.gz /tmp/whatap.tar.gz
COPY paramkey.txt /whatap/paramkey.txt

RUN set -eux; \
    tar -xzf /tmp/whatap.tar.gz -C /whatap --strip-components=1; \
    rm -f /tmp/whatap.tar.gz; \
    \
    # ✅ 버전 명시된 jar가 반드시 있어야 함
    test -f /whatap/whatap.agent-2.2.67.jar; \
    test -f /whatap/whatap.conf; \
    chmod -R a=rX /whatap

# =========================
# 3) Runtime
# =========================
FROM gcr.io/distroless/java21-debian12:nonroot
WORKDIR /app

COPY --from=builder /app/app.jar /app/app.jar
COPY --from=whatap_agent --chown=65532:65532 /whatap /whatap

ENV JAVA_HOME=/opt/java/openjdk
ENV WHATAP_HOME=/whatap

# ✅ 공식 문서 그대로 "버전 명시"
ENV JAVA_TOOL_OPTIONS="\
-javaagent:/whatap/whatap.agent-2.2.67.jar \
-Dwhatap.home=/whatap \
-Dwhatap.paramkey=/whatap/paramkey.txt \
-Dwhatap.micro.enabled=true \
--add-opens=java.base/java.lang=ALL-UNNAMED \
-XX:+UseContainerSupport \
-XX:MaxRAMPercentage=75 \
-XX:+ExitOnOutOfMemoryError"

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
