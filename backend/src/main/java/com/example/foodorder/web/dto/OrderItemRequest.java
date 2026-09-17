package com.example.foodorder.web.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * A single requested line of an order.
 */
public record OrderItemRequest(
        @NotNull(message = "productId must not be null")
        Long productId,

        @Positive(message = "quantity must be greater than 0")
        int quantity) {
}
