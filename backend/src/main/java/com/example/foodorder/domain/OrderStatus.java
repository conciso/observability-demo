package com.example.foodorder.domain;

/**
 * Lifecycle status of an {@link Order}. Kept intentionally small for the demo.
 */
public enum OrderStatus {
    CREATED,
    PAID,
    SHIPPED,
    CANCELLED
}
