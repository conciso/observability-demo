# syntax=docker/dockerfile:1

##########################################################################
# Build stage - JDK 25 + Gradle wrapper build the bootable jar
##########################################################################
FROM eclipse-temurin:25.0.5_8-jdk AS build
WORKDIR /workspace

# Copy build definition first so dependency resolution is cached independently of sources.
COPY gradlew settings.gradle build.gradle ./
COPY gradle ./gradle
RUN chmod +x gradlew && ./gradlew --no-daemon dependencies > /dev/null

# Copy sources and build the Spring Boot bootable jar (tests run in CI, skipped here).
COPY src ./src
RUN ./gradlew --no-daemon clean bootJar -x test

##########################################################################
# Runtime stage - slim JRE 25 + OpenTelemetry Java agent
##########################################################################
FROM eclipse-temurin:25.0.5_8-jre AS runtime
WORKDIR /app

# OpenTelemetry Java agent (auto-instrumentation, no application code required).
# Pinned for reproducible builds; bump the version deliberately.
ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.33.1/opentelemetry-javaagent.jar /otel/opentelemetry-javaagent.jar

COPY --from=build /workspace/build/libs/*.jar /app/app.jar

# The agent's OTEL_* settings (service name, OTLP endpoint, exporters, resource
# attributes) live in docker-compose.yml only, so there is a single source of truth.
ENV JAVA_TOOL_OPTIONS="-javaagent:/otel/opentelemetry-javaagent.jar"

EXPOSE 8081

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
