package com.example.foodorder.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.example.foodorder.domain.Order;
import com.example.foodorder.domain.Product;
import com.example.foodorder.repository.OrderRepository;
import com.example.foodorder.repository.ProductRepository;
import com.example.foodorder.service.exception.ProductNotFoundException;
import com.example.foodorder.web.dto.CreateOrderRequest;
import com.example.foodorder.web.dto.OrderItemRequest;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import io.micrometer.observation.tck.TestObservationRegistry;
import io.micrometer.observation.tck.TestObservationRegistryAssert;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * Test type 2 - Observation API test.
 *
 * <p>Verifies, via a {@link TestObservationRegistry} and AssertJ observation assertions, that
 * creating an order produces the {@code orders.create} observation with the expected business
 * key-values. No Spring context and no OTel agent are involved.
 */
@ExtendWith(MockitoExtension.class)
class OrderObservationTest {

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private ProductRepository productRepository;

    private TestObservationRegistry observationRegistry;
    private OrderService orderService;

    private final Product pizza = new Product("Pizza Margherita", "Classic", 899, "Food");
    private final Product water = new Product("Sparkling Water", "0.5l", 150, "Drinks");

    @BeforeEach
    void setUp() {
        observationRegistry = TestObservationRegistry.create();
        OrderMetrics orderMetrics = new OrderMetrics(new SimpleMeterRegistry());
        orderService = new OrderService(orderRepository, productRepository, orderMetrics,
                observationRegistry);
    }

    @Test
    @DisplayName("creates an 'orders.create' observation with business key-values")
    void createsOrdersCreateObservation() {
        when(orderRepository.save(any(Order.class))).thenAnswer(inv -> inv.getArgument(0));
        when(productRepository.findById(1L)).thenReturn(Optional.of(pizza));
        when(productRepository.findById(2L)).thenReturn(Optional.of(water));
        // 2 line items -> item_count=2; 2x899 + 3x150 = 2248 cents
        CreateOrderRequest request = new CreateOrderRequest("Ada", List.of(
                new OrderItemRequest(1L, 2),
                new OrderItemRequest(2L, 3)));

        orderService.createOrder(request);

        TestObservationRegistryAssert.assertThat(observationRegistry)
                .hasNumberOfObservationsEqualTo(1)
                .hasSingleObservationThat()
                .hasNameEqualTo("orders.create")
                .hasBeenStarted()
                .hasBeenStopped()
                .doesNotHaveError()
                .hasLowCardinalityKeyValue("order.item_count", "2")
                .hasHighCardinalityKeyValue("order.value_cents", "2248");
    }

    @Test
    @DisplayName("marks the observation as errored when a product is unknown")
    void marksObservationErroredOnUnknownProduct() {
        when(productRepository.findById(99L)).thenReturn(Optional.empty());
        CreateOrderRequest request = new CreateOrderRequest(
                "Ada", List.of(new OrderItemRequest(99L, 1)));

        try {
            orderService.createOrder(request);
        } catch (ProductNotFoundException expected) {
            // expected - the observation must still be recorded and flagged with the error
        }

        TestObservationRegistryAssert.assertThat(observationRegistry)
                .hasSingleObservationThat()
                .hasNameEqualTo("orders.create")
                .hasBeenStarted()
                .hasBeenStopped()
                .assertThatError()
                .isInstanceOf(ProductNotFoundException.class);
    }
}
