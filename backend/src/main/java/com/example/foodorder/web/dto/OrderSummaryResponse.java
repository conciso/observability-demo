package com.example.foodorder.web.dto;

import com.example.foodorder.domain.Order;
import com.example.foodorder.domain.OrderStatus;
import java.time.OffsetDateTime;

/**
 * Condensed API representation of an order for list views (no line items).
 */
public record OrderSummaryResponse(
        Long id,
        OffsetDateTime createdAt,
        OrderStatus status,
        String customerName,
        long totalCents,
        double totalEuros,
        int itemCount) {

    public static OrderSummaryResponse from(Order order) {
        return new OrderSummaryResponse(
                order.getId(),
                order.getCreatedAt(),
                order.getStatus(),
                order.getCustomerName(),
                order.getTotalCents(),
                order.getTotalCents() / 100.0,
                order.getItems().size());
    }
}
