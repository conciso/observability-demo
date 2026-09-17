package com.example.foodorder.web;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestClient;

/**
 * Test type 4 - Actuator / web-slice test.
 *
 * <p>Runs the full application on a random port (so the real {@code ServerHttpObservationFilter}
 * is in the request path) and verifies that {@code /actuator/prometheus} returns 200 and exposes
 * both the auto-instrumented HTTP server metrics and the business metrics, after an endpoint has
 * been called.
 *
 * <p>Note: Spring Boot 4 removed {@code @AutoConfigureObservability} and {@code TestRestTemplate};
 * using a real server ({@code RANDOM_PORT}) with a {@link RestClient} is the idiomatic replacement
 * that guarantees HTTP server observations are recorded.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ActuatorPrometheusMetricsTest {

    @LocalServerPort
    private int port;

    private RestClient client;

    @BeforeEach
    void setUp() {
        client = RestClient.builder().baseUrl("http://localhost:" + port).build();
    }

    @Test
    @DisplayName("/actuator/prometheus exposes HTTP server and business metrics")
    void prometheusEndpointExposesMetrics() {
        // Trigger an observed server request so http.server.requests is recorded.
        ResponseEntity<String> products = client.get().uri("/api/products").retrieve().toEntity(String.class);
        assertThat(products.getStatusCode()).isEqualTo(HttpStatus.OK);

        ResponseEntity<String> scrape = client.get().uri("/actuator/prometheus").retrieve().toEntity(String.class);

        assertThat(scrape.getStatusCode()).isEqualTo(HttpStatus.OK);
        String body = scrape.getBody();
        assertThat(body).isNotNull();
        // Auto-instrumented HTTP server metric (Micrometer/Observation).
        assertThat(body).contains("http_server_requests_seconds");
        // Business metrics under their exact names.
        assertThat(body).contains("orders_created_total");
        assertThat(body).contains("order_value_euros_count");
    }
}
