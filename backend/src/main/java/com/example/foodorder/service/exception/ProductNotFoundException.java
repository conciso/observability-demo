package com.example.foodorder.service.exception;

/**
 * Thrown when an order references a product id that does not exist. Mapped to HTTP 404.
 */
public class ProductNotFoundException extends RuntimeException {

    public ProductNotFoundException(Long productId) {
        super("Product not found: " + productId);
    }
}
