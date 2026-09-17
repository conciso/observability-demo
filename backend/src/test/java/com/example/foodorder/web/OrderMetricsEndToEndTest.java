package com.example.foodorder.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

import com.example.foodorder.web.dto.CreateOrderRequest;
import com.example.foodorder.web.dto.OrderItemRequest;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestClient;

/**
 * Test type 5 - full-stack {@code @SpringBootTest(RANDOM_PORT)} with real H2 + Flyway.
 *
 * <p>Scrapes {@code /actuator/prometheus} before and after driving traffic and asserts on the
 * exact Prometheus series names and their deltas: {@code orders_created_total} rises by exactly
 * the number of successful orders (a failed order does not count) and {@code order_value_euros_sum}
 * rises by the total ordered value. Values are extracted with a regex text parser, not a naive
 * {@code contains} check.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OrderMetricsEndToEndTest {

    private static final int SUCCESSFUL_ORDERS = 3;
    // Product id 1 is "Bio-Aepfel 1 kg" from the V2 seed migration: 299 cents = 2.99 EUR.
    private static final long PRODUCT_ID = 1L;
    private static final double PRODUCT_PRICE_EUROS = 2.99;

    @LocalServerPort
    private int port;

    private RestClient client;

    @BeforeEach
    void setUp() {
        // Do not throw on 4xx/5xx so the invalid-order response can be asserted on its status.
        client = RestClient.builder()
                .baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> {
                })
                .build();
    }

    @Test
    @DisplayName("orders_created_total and order_value_euros_sum increase by exactly the traffic")
    void businessMetricsReflectTrafficExactly() {
        String before = scrape();
        double createdBefore = metricValue(before, "orders_created_total");
        double valueSumBefore = metricValue(before, "order_value_euros_sum");

        // N valid orders ...
        for (int i = 0; i < SUCCESSFUL_ORDERS; i++) {
            ResponseEntity<String> resp = postOrder(PRODUCT_ID, 1);
            assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        }
        // ... plus one invalid order (unknown product) that must NOT be counted.
        ResponseEntity<String> invalid = postOrder(999_999L, 1);
        assertThat(invalid.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);

        String after = scrape();

        // Exact series names must all be present.
        assertThat(after)
                .contains("orders_created_total")
                .contains("order_value_euros_count")
                .contains("order_value_euros_sum")
                .contains("order_value_euros_bucket{");

        double createdAfter = metricValue(after, "orders_created_total");
        double valueSumAfter = metricValue(after, "order_value_euros_sum");

        // orders_created_total rose by exactly N (the failed order did not count).
        assertThat(createdAfter - createdBefore).isEqualTo((double) SUCCESSFUL_ORDERS);
        // order_value_euros_sum rose by the total ordered value.
        assertThat(valueSumAfter - valueSumBefore)
                .isCloseTo(SUCCESSFUL_ORDERS * PRODUCT_PRICE_EUROS, within(0.0001));
    }

    private ResponseEntity<String> postOrder(long productId, int quantity) {
        CreateOrderRequest request = new CreateOrderRequest(
                "E2E-Customer", List.of(new OrderItemRequest(productId, quantity)));
        return client.post().uri("/api/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .body(request)
                .retrieve()
                .toEntity(String.class);
    }

    private String scrape() {
        ResponseEntity<String> resp = client.get().uri("/actuator/prometheus").retrieve().toEntity(String.class);
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(resp.getBody()).isNotNull();
        return resp.getBody();
    }

    /**
     * Extracts the value of a label-less Prometheus sample line, e.g. {@code orders_created_total 3.0}.
     * Returns 0.0 if the series is not present yet.
     */
    private static double metricValue(String body, String metricName) {
        Matcher matcher = Pattern.compile(
                "(?m)^" + Pattern.quote(metricName) + "\\s+([0-9eE.+-]+)$").matcher(body);
        return matcher.find() ? Double.parseDouble(matcher.group(1)) : 0.0;
    }
}
