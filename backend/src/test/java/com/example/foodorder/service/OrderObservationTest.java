package com.example.foodorder.service;

import static com.example.foodorder.service.OrderFixtures.TWO_ITEM_ORDER_TOTAL_CENTS;
import static com.example.foodorder.service.OrderFixtures.stubTwoItemOrder;
import static com.example.foodorder.service.OrderFixtures.twoItemOrder;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

import com.example.foodorder.repository.OrderRepository;
import com.example.foodorder.repository.ProductRepository;
import com.example.foodorder.service.exception.ProductNotFoundException;
import com.example.foodorder.web.dto.CreateOrderRequest;
import com.example.foodorder.web.dto.OrderItemRequest;
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

    @BeforeEach
    void setUp() {
        observationRegistry = TestObservationRegistry.create();
        orderService = OrderFixtures.orderService(orderRepository, productRepository, observationRegistry);
    }

    @Test
    @DisplayName("creates an 'orders.create' observation with business key-values")
    void createsOrdersCreateObservation() {
        stubTwoItemOrder(orderRepository, productRepository);

        orderService.createOrder(twoItemOrder());

        TestObservationRegistryAssert.assertThat(observationRegistry)
                .hasNumberOfObservationsEqualTo(1)
                .hasSingleObservationThat()
                .hasNameEqualTo("orders.create")
                .hasBeenStarted()
                .hasBeenStopped()
                .doesNotHaveError()
                .hasLowCardinalityKeyValue("order.item_count", "2")
                .hasHighCardinalityKeyValue("order.value_cents", Long.toString(TWO_ITEM_ORDER_TOTAL_CENTS));
    }

    @Test
    @DisplayName("marks the observation as errored when a product is unknown")
    void marksObservationErroredOnUnknownProduct() {
        when(productRepository.findById(99L)).thenReturn(Optional.empty());
        CreateOrderRequest request = new CreateOrderRequest(
                "Ada", List.of(new OrderItemRequest(99L, 1)));

        // The exception must still propagate; the observation is recorded and flagged with it.
        assertThatThrownBy(() -> orderService.createOrder(request))
                .isInstanceOf(ProductNotFoundException.class);

        TestObservationRegistryAssert.assertThat(observationRegistry)
                .hasSingleObservationThat()
                .hasNameEqualTo("orders.create")
                .hasBeenStarted()
                .hasBeenStopped()
                .assertThatError()
                .isInstanceOf(ProductNotFoundException.class);
    }
}
