package com.example.foodorder.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * A customer order. Monetary totals are stored as integer cents. The order total is
 * always derived from its items via {@link #recalculateTotal()} and never trusted from
 * the client.
 */
@Entity
@Table(name = "orders")
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private OrderStatus status;

    @Column(name = "total_cents", nullable = false)
    private long totalCents;

    @Column(name = "customer_name", nullable = false)
    private String customerName;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<OrderItem> items = new ArrayList<>();

    protected Order() {
        // Required by JPA.
    }

    public Order(String customerName) {
        this.customerName = customerName;
        this.createdAt = OffsetDateTime.now();
        this.status = OrderStatus.CREATED;
    }

    /**
     * Adds an item and keeps both sides of the bidirectional association in sync.
     */
    public void addItem(OrderItem item) {
        item.setOrder(this);
        this.items.add(item);
    }

    /**
     * Recomputes {@link #totalCents} from the current items. Call after all items are added.
     */
    public void recalculateTotal() {
        long sum = 0;
        for (OrderItem item : items) {
            sum += item.getLineTotalCents();
        }
        this.totalCents = sum;
    }

    public Long getId() {
        return id;
    }

    public OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    public OrderStatus getStatus() {
        return status;
    }

    public void setStatus(OrderStatus status) {
        this.status = status;
    }

    public long getTotalCents() {
        return totalCents;
    }

    public String getCustomerName() {
        return customerName;
    }

    public List<OrderItem> getItems() {
        return Collections.unmodifiableList(items);
    }
}
