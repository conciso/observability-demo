package com.example.foodorder.web.dto;

import com.example.foodorder.domain.Product;

/**
 * API representation of a product. Exposes both the raw cents and a convenience euro value.
 */
public record ProductResponse(
        Long id,
        String name,
        String description,
        int priceCents,
        double priceEuros,
        String category) {

    public static ProductResponse from(Product product) {
        return new ProductResponse(
                product.getId(),
                product.getName(),
                product.getDescription(),
                product.getPriceCents(),
                product.getPriceCents() / 100.0,
                product.getCategory());
    }
}
