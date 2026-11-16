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
 * Test type 4 - Actuator test against the full application.
 *
 * <p>Runs the full application on a random port (so the real {@code ServerHttpObservationFilter}
 * is in the request path) and verifies that {@code /actuator/prometheus} returns 200 and exposes
 * the auto-instrumented HTTP server metric for the endpoint that was called, plus the business
 * metrics.
 *
 * <p>A plain {@link RestClient} against the real server is used instead of
 * {@code TestRestTemplate}, which in Spring Boot 4 lives in the separate
 * {@code spring-boot-resttestclient} module.
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
        // Auto-instrumented HTTP server metric for exactly the request made above. A plain
        // "contains" would also match the scrape request itself or the # HELP line.
        assertThat(body.lines())
                .anyMatch(line -> line.startsWith("http_server_requests_seconds_count{")
                        && line.contains("uri=\"/api/products\"")
                        && line.contains("status=\"200\""));
        // Business metrics under their exact names (as samples, not just in # HELP/# TYPE).
        assertThat(body.lines())
                .anyMatch(line -> line.startsWith("orders_created_total "))
                .anyMatch(line -> line.startsWith("order_value_euros_count "));
    }
}
