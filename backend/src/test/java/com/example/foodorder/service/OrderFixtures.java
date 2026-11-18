package com.example.foodorder.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.example.foodorder.domain.Order;
import com.example.foodorder.domain.Product;
import com.example.foodorder.repository.OrderRepository;
import com.example.foodorder.repository.ProductRepository;
import com.example.foodorder.web.dto.CreateOrderRequest;
import com.example.foodorder.web.dto.OrderItemRequest;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import io.micrometer.observation.ObservationRegistry;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Shared test data and wiring for the {@link OrderService} unit tests.
 */
final class OrderFixtures {

    static final long PIZZA_ID = 1L;
    static final long WATER_ID = 2L;

    /** 2 line items: 2 x 899 + 3 x 150 = 2248 cents. */
    static final long TWO_ITEM_ORDER_TOTAL_CENTS = 2248L;

    private OrderFixtures() {
    }

    static Product pizza() {
        return new Product("Pizza Margherita", "Classic", 899, "Food");
    }

    static Product water() {
        return new Product("Sparkling Water", "0.5l", 150, "Drinks");
    }

    /** Ada orders 2 pizzas and 3 waters, see {@link #TWO_ITEM_ORDER_TOTAL_CENTS}. */
    static CreateOrderRequest twoItemOrder() {
        return new CreateOrderRequest("Ada", List.of(
                new OrderItemRequest(PIZZA_ID, 2),
                new OrderItemRequest(WATER_ID, 3)));
    }

    /** Wires an {@link OrderService} with throw-away metrics, for tests that do not assert on them. */
    static OrderService orderService(OrderRepository orderRepository,
                                     ProductRepository productRepository,
                                     ObservationRegistry observationRegistry) {
        return new OrderService(orderRepository, productRepository,
                new OrderMetrics(new SimpleMeterRegistry()), observationRegistry);
    }

    /** orderRepository.save returns the order as-is (persistence is not under test here). */
    static void stubSaveReturnsArgument(OrderRepository orderRepository) {
        when(orderRepository.save(any(Order.class))).thenAnswer(inv -> inv.getArgument(0));
    }

    static void stubProducts(ProductRepository productRepository, Map<Long, Product> products) {
        products.forEach((id, product) ->
                when(productRepository.findById(id)).thenReturn(Optional.of(product)));
    }

    /** Stubs the catalog and save() for {@link #twoItemOrder()}. */
    static void stubTwoItemOrder(OrderRepository orderRepository, ProductRepository productRepository) {
        stubSaveReturnsArgument(orderRepository);
        stubProducts(productRepository, Map.of(PIZZA_ID, pizza(), WATER_ID, water()));
    }
}