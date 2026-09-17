package com.example.foodorder.web.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import java.util.List;

/**
 * Request body for creating an order. Prices are never accepted from the client; the
 * server derives them from the current product catalog.
 */
public record CreateOrderRequest(
        @NotBlank(message = "customerName must not be blank")
        String customerName,

        @NotEmpty(message = "an order must contain at least one item")
        List<@Valid OrderItemRequest> items) {
}
