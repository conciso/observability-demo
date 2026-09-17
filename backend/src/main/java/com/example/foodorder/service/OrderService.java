package com.example.foodorder.service;

import com.example.foodorder.domain.Order;
import com.example.foodorder.domain.OrderItem;
import com.example.foodorder.domain.Product;
import com.example.foodorder.repository.OrderRepository;
import com.example.foodorder.repository.ProductRepository;
import com.example.foodorder.service.exception.OrderNotFoundException;
import com.example.foodorder.service.exception.ProductNotFoundException;
import com.example.foodorder.web.dto.CreateOrderRequest;
import com.example.foodorder.web.dto.OrderItemRequest;
import com.example.foodorder.web.dto.OrderResponse;
import com.example.foodorder.web.dto.OrderSummaryResponse;
import io.micrometer.observation.Observation;
import io.micrometer.observation.ObservationRegistry;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Order use cases: creating an order (with server-side price calculation) and reading
 * orders back. Emits the demo's business metrics on every successful order.
 *
 * <p>Order creation is wrapped in an {@link Observation} named {@code orders.create} carrying
 * business attributes ({@code order.item_count}, {@code order.value_cents}). In production the
 * OpenTelemetry Java agent turns this into a span with those attributes and a matching
 * {@code orders.create} timer; it also makes the flow assertable in-JVM (without the agent)
 * via a {@code TestObservationRegistry} or an OTel-SDK tracing bridge.
 *
 * <p>Entities are mapped to DTOs inside the transactional methods so that lazily loaded
 * associations (order items) are always initialized before leaving the persistence context.
 */
@Service
public class OrderService {

    private static final Logger log = LoggerFactory.getLogger(OrderService.class);

    private final OrderRepository orderRepository;
    private final ProductRepository productRepository;
    private final OrderMetrics orderMetrics;
    private final ObservationRegistry observationRegistry;

    public OrderService(OrderRepository orderRepository,
                        ProductRepository productRepository,
                        OrderMetrics orderMetrics,
                        ObservationRegistry observationRegistry) {
        this.orderRepository = orderRepository;
        this.productRepository = productRepository;
        this.orderMetrics = orderMetrics;
        this.observationRegistry = observationRegistry;
    }

    /**
     * Creates and persists a new order. Line and total prices are computed on the server
     * from the current catalog; the client cannot influence pricing.
     *
     * @throws ProductNotFoundException if any referenced product does not exist
     */
    @Transactional
    public OrderResponse createOrder(CreateOrderRequest request) {
        Observation observation = Observation.createNotStarted("orders.create", observationRegistry);
        return observation.observe(() -> {
            Order order = new Order(request.customerName());

            for (OrderItemRequest itemRequest : request.items()) {
                Product product = productRepository.findById(itemRequest.productId())
                        .orElseThrow(() -> new ProductNotFoundException(itemRequest.productId()));
                order.addItem(new OrderItem(product, itemRequest.quantity()));
            }
            order.recalculateTotal();

            Order saved = orderRepository.save(order);

            observation.lowCardinalityKeyValue("order.item_count", Integer.toString(saved.getItems().size()));
            observation.highCardinalityKeyValue("order.value_cents", Long.toString(saved.getTotalCents()));

            orderMetrics.recordCreatedOrder(saved.getTotalCents());
            log.info("Created order id={} for customer='{}' with {} item(s), total={} cents",
                    saved.getId(), saved.getCustomerName(), saved.getItems().size(), saved.getTotalCents());

            return OrderResponse.from(saved);
        });
    }

    @Transactional(readOnly = true)
    public OrderResponse findById(Long id) {
        Order order = orderRepository.findById(id)
                .orElseThrow(() -> new OrderNotFoundException(id));
        return OrderResponse.from(order);
    }

    @Transactional(readOnly = true)
    public List<OrderSummaryResponse> findAll() {
        return orderRepository.findAll().stream()
                .map(OrderSummaryResponse::from)
                .toList();
    }
}
