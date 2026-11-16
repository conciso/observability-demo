package com.example.foodorder.service;

import static com.example.foodorder.service.OrderFixtures.PIZZA_ID;
import static com.example.foodorder.service.OrderFixtures.TWO_ITEM_ORDER_TOTAL_CENTS;
import static com.example.foodorder.service.OrderFixtures.pizza;
import static com.example.foodorder.service.OrderFixtures.stubProducts;
import static com.example.foodorder.service.OrderFixtures.stubSaveReturnsArgument;
import static com.example.foodorder.service.OrderFixtures.stubTwoItemOrder;
import static com.example.foodorder.service.OrderFixtures.twoItemOrder;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.Mockito.when;

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
import org.assertj.core.data.Offset;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    /** Euro values are doubles derived from cents; compare them with a tolerance. */
    private static final Offset<Double> EURO_TOLERANCE = within(1e-9);

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private ProductRepository productRepository;

    private MeterRegistry meterRegistry;
    private OrderMetrics orderMetrics;
    private OrderService orderService;

    @BeforeEach
    void setUp() {
        meterRegistry = new SimpleMeterRegistry();
        orderMetrics = new OrderMetrics(meterRegistry);
        // NOOP registry: the observed code still runs; observation behaviour is covered by
        // OrderObservationTest / OrderTracingTest.
        orderService = new OrderService(orderRepository, productRepository, orderMetrics,
                ObservationRegistry.NOOP);
    }

    @Test
    @DisplayName("computes line and total prices server-side from the current catalog")
    void computesTotalFromCatalog() {
        stubTwoItemOrder(orderRepository, productRepository);

        OrderResponse response = orderService.createOrder(twoItemOrder());

        assertThat(response.totalCents()).isEqualTo(TWO_ITEM_ORDER_TOTAL_CENTS);
        assertThat(response.totalEuros()).isCloseTo(22.48, EURO_TOLERANCE);
        assertThat(response.customerName()).isEqualTo("Ada");
        assertThat(response.items()).hasSize(2);
        assertThat(response.items().get(0).lineTotalCents()).isEqualTo(1798L);  // 2 x 899
        assertThat(response.items().get(0).unitPriceCents()).isEqualTo(899L);
        assertThat(response.items().get(1).lineTotalCents()).isEqualTo(450L);   // 3 x 150
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
        stubSaveReturnsArgument(orderRepository);
        stubProducts(productRepository, Map.of(PIZZA_ID, pizza()));
        CreateOrderRequest request = new CreateOrderRequest(
                "Grace", List.of(new OrderItemRequest(PIZZA_ID, 1)));

        orderService.createOrder(request);

        assertThat(orderMetrics.ordersCreatedCount()).isEqualTo(1.0);
        DistributionSummary summary = meterRegistry.get("order.value.euros").summary();
        assertThat(summary.count()).isEqualTo(1L);
        assertThat(summary.totalAmount()).isCloseTo(8.99, EURO_TOLERANCE);
    }

    @Test
    @DisplayName("accumulates counter and value summary across multiple orders (delta)")
    void accumulatesAcrossMultipleOrders() {
        stubSaveReturnsArgument(orderRepository);
        stubProducts(productRepository, Map.of(PIZZA_ID, pizza())); // 899 cents = 8.99 EUR each

        orderService.createOrder(new CreateOrderRequest("A", List.of(new OrderItemRequest(PIZZA_ID, 1))));
        orderService.createOrder(new CreateOrderRequest("B", List.of(new OrderItemRequest(PIZZA_ID, 2))));
        orderService.createOrder(new CreateOrderRequest("C", List.of(new OrderItemRequest(PIZZA_ID, 1))));

        assertThat(orderMetrics.ordersCreatedCount()).isEqualTo(3.0);
        DistributionSummary summary = meterRegistry.get("order.value.euros").summary();
        assertThat(summary.count()).isEqualTo(3L);
        // 8.99 + 17.98 + 8.99 = 35.96
        assertThat(summary.totalAmount()).isCloseTo(35.96, EURO_TOLERANCE);
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
