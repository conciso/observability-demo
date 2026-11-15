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

# --- OpenTelemetry defaults (all overridable via docker-compose) ---
# Traces + logs are exported via OTLP to the collector. Metrics are scraped from
# /actuator/prometheus by Prometheus, so the agent's metric exporter is disabled to
# avoid double collection (see PLANUNG.md sections 6 and 8).
ENV JAVA_TOOL_OPTIONS="-javaagent:/otel/opentelemetry-javaagent.jar"
ENV OTEL_SERVICE_NAME=food-order-backend
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
ENV OTEL_EXPORTER_OTLP_PROTOCOL=grpc
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_LOGS_EXPORTER=otlp
ENV OTEL_METRICS_EXPORTER=none
ENV OTEL_RESOURCE_ATTRIBUTES=service.namespace=food-order,deployment.environment=demo

EXPOSE 8081

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
