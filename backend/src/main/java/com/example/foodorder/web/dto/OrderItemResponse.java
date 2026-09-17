package com.example.foodorder.web.dto;

import com.example.foodorder.domain.OrderItem;

/**
 * API representation of a single order line.
 */
public record OrderItemResponse(
        Long id,
        Long productId,
        String productName,
        int quantity,
        long unitPriceCents,
        long lineTotalCents) {

    public static OrderItemResponse from(OrderItem item) {
        return new OrderItemResponse(
                item.getId(),
                item.getProduct().getId(),
                item.getProduct().getName(),
                item.getQuantity(),
                item.getUnitPriceCents(),
                item.getLineTotalCents());
    }
}
