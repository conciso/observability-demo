package com.example.foodorder.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.example.foodorder.domain.Order;
import com.example.foodorder.domain.Product;
import com.example.foodorder.repository.OrderRepository;
import com.example.foodorder.repository.ProductRepository;
import com.example.foodorder.service.exception.ProductNotFoundException;
import com.example.foodorder.web.dto.CreateOrderRequest;
import com.example.foodorder.web.dto.OrderItemRequest;
import com.example.foodorder.web.dto.OrderResponse;
import io.micrometer.core.instrument.DistributionSummary;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import io.micrometer.observation.ObservationRegistry;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private ProductRepository productRepository;

    private MeterRegistry meterRegistry;
    private OrderMetrics orderMetrics;
    private OrderService orderService;

    private final Product pizza = new Product("Pizza Margherita", "Classic", 899, "Food");
    private final Product water = new Product("Sparkling Water", "0.5l", 150, "Drinks");

    @BeforeEach
    void setUp() {
        meterRegistry = new SimpleMeterRegistry();
        orderMetrics = new OrderMetrics(meterRegistry);
        // NOOP registry: the observed code still runs; observation behaviour is covered by
        // OrderObservationTest / OrderTracingTest.
        orderService = new OrderService(orderRepository, productRepository, orderMetrics,
                ObservationRegistry.NOOP);
    }

    /** orderRepository.save returns the order as-is (persistence is not under test here). */
    private void stubSaveReturnsArgument() {
        when(orderRepository.save(any(Order.class))).thenAnswer(inv -> inv.getArgument(0));
    }

    private void stubProducts(Map<Long, Product> products) {
        products.forEach((id, product) ->
                when(productRepository.findById(id)).thenReturn(Optional.of(product)));
    }

    @Test
    @DisplayName("computes line and total prices server-side from the current catalog")
    void computesTotalFromCatalog() {
        stubSaveReturnsArgument();
        stubProducts(Map.of(1L, pizza, 2L, water));
        CreateOrderRequest request = new CreateOrderRequest("Ada", List.of(
                new OrderItemRequest(1L, 2),   // 2 x 899 = 1798
                new OrderItemRequest(2L, 3)));  // 3 x 150 = 450

        OrderResponse response = orderService.createOrder(request);

        assertThat(response.totalCents()).isEqualTo(2248L);
        assertThat(response.totalEuros()).isEqualTo(22.48);
        assertThat(response.customerName()).isEqualTo("Ada");
        assertThat(response.items()).hasSize(2);
        assertThat(response.items().get(0).lineTotalCents()).isEqualTo(1798L);
        assertThat(response.items().get(0).unitPriceCents()).isEqualTo(899L);
        assertThat(response.items().get(1).lineTotalCents()).isEqualTo(450L);
    }

    @Test
    @DisplayName("rejects an order that references an unknown product")
    void rejectsUnknownProduct() {
        when(productRepository.findById(99L)).thenReturn(Optional.empty());
        CreateOrderRequest request = new CreateOrderRequest(
                "Ada", List.of(new OrderItemRequest(99L, 1)));

        assertThatThrownBy(() -> orderService.createOrder(request))
                .isInstanceOf(ProductNotFoundException.class)
                .hasMessageContaining("99");
    }

    @Test
    @DisplayName("emits business metrics on a successful order")
    void emitsBusinessMetrics() {
        stubSaveReturnsArgument();
        stubProducts(Map.of(1L, pizza));
        CreateOrderRequest request = new CreateOrderRequest(
                "Grace", List.of(new OrderItemRequest(1L, 1)));

        orderService.createOrder(request);

        assertThat(orderMetrics.ordersCreatedCount()).isEqualTo(1.0);
        DistributionSummary summary = meterRegistry.get("order.value.euros").summary();
        assertThat(summary.count()).isEqualTo(1L);
        assertThat(summary.totalAmount()).isEqualTo(8.99);
    }

    @Test
    @DisplayName("accumulates counter and value summary across multiple orders (delta)")
    void accumulatesAcrossMultipleOrders() {
        stubSaveReturnsArgument();
        stubProducts(Map.of(1L, pizza)); // 899 cents = 8.99 EUR each

        orderService.createOrder(new CreateOrderRequest("A", List.of(new OrderItemRequest(1L, 1))));
        orderService.createOrder(new CreateOrderRequest("B", List.of(new OrderItemRequest(1L, 2))));
        orderService.createOrder(new CreateOrderRequest("C", List.of(new OrderItemRequest(1L, 1))));

        assertThat(orderMetrics.ordersCreatedCount()).isEqualTo(3.0);
        DistributionSummary summary = meterRegistry.get("order.value.euros").summary();
        assertThat(summary.count()).isEqualTo(3L);
        // 8.99 + 17.98 + 8.99 = 35.96
        assertThat(summary.totalAmount()).isEqualTo(35.96);
    }

    @Test
    @DisplayName("does not count an order that fails because a product does not exist")
    void doesNotCountFailedOrder() {
        when(productRepository.findById(99L)).thenReturn(Optional.empty());
        CreateOrderRequest request = new CreateOrderRequest(
                "Ada", List.of(new OrderItemRequest(99L, 1)));

        assertThatThrownBy(() -> orderService.createOrder(request))
                .isInstanceOf(ProductNotFoundException.class);

        assertThat(orderMetrics.ordersCreatedCount()).isEqualTo(0.0);
    }
}
