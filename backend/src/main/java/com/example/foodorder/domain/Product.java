package com.example.foodorder.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A food product that can be ordered. Prices are stored as integer cents to avoid
 * floating-point rounding issues.
 */
@Entity
@Table(name = "products")
public class Product {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    @Column(length = 1000)
    private String description;

    @Column(name = "price_cents", nullable = false)
    private int priceCents;

    @Column(nullable = false, length = 100)
    private String category;

    protected Product() {
        // Required by JPA.
    }

    public Product(String name, String description, int priceCents, String category) {
        this.name = name;
        this.description = description;
        this.priceCents = priceCents;
        this.category = category;
    }

    public Long getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public String getDescription() {
        return description;
    }

    public int getPriceCents() {
        return priceCents;
    }

    public String getCategory() {
        return category;
    }
}
