package com.example.foodorder.service.exception;

/**
 * Thrown when an order id cannot be found. Mapped to HTTP 404.
 */
public class OrderNotFoundException extends RuntimeException {

    public OrderNotFoundException(Long orderId) {
        super("Order not found: " + orderId);
    }
}
