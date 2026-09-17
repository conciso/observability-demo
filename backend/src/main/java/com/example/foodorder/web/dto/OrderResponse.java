package com.example.foodorder.web.dto;

import com.example.foodorder.domain.Order;
import com.example.foodorder.domain.OrderStatus;
import java.time.OffsetDateTime;
import java.util.List;

/**
 * Full API representation of an order including its line items.
 */
public record OrderResponse(
        Long id,
        OffsetDateTime createdAt,
        OrderStatus status,
        String customerName,
        long totalCents,
        double totalEuros,
        List<OrderItemResponse> items) {

    public static OrderResponse from(Order order) {
        List<OrderItemResponse> itemResponses = order.getItems().stream()
                .map(OrderItemResponse::from)
                .toList();
        return new OrderResponse(
                order.getId(),
                order.getCreatedAt(),
                order.getStatus(),
                order.getCustomerName(),
                order.getTotalCents(),
                order.getTotalCents() / 100.0,
                itemResponses);
    }
}
