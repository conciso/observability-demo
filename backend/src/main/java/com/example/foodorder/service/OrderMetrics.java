package com.example.foodorder.service;

import io.micrometer.core.instrument.DistributionSummary;
import io.micrometer.core.instrument.MeterRegistry;
import java.util.concurrent.atomic.LongAdder;
import org.springframework.stereotype.Component;

/**
 * Business metrics for the ordering flow. Single source of truth for both demo metrics:
 *
 * <ul>
 *   <li>{@code order_value_euros} - a Micrometer {@link DistributionSummary} of order values.</li>
 *   <li>{@code orders_created_total} - the number of successfully created orders.</li>
 * </ul>
 *
 * <p>The created-order count is held in a {@link LongAdder} and exposed under the exact
 * Prometheus name {@code orders_created_total} by {@code PrometheusBusinessMetricsConfig}.
 * A plain Micrometer {@code Counter} cannot be used for this one metric because Micrometer's
 * Prometheus client (1.x) strips the reserved trailing suffix {@code _created}, which would
 * render the series as {@code orders_total} instead of the required {@code orders_created_total}.
 */
@Component
public class OrderMetrics {

    private final DistributionSummary orderValueSummary;
    private final LongAdder ordersCreated = new LongAdder();

    public OrderMetrics(MeterRegistry meterRegistry) {
        this.orderValueSummary = DistributionSummary.builder("order.value.euros")
                .description("Distribution of order values in euros")
                .baseUnit("euros")
                .publishPercentileHistogram()
                .register(meterRegistry);
    }

    /**
     * Records a single successfully created order: bumps the counter and adds its value
     * to the distribution summary.
     *
     * @param totalCents the order total in cents
     */
    public void recordCreatedOrder(long totalCents) {
        ordersCreated.increment();
        orderValueSummary.record(totalCents / 100.0);
    }

    /**
     * @return the current number of created orders (backing value for {@code orders_created_total}).
     */
    public double ordersCreatedCount() {
        return ordersCreated.sum();
    }
}
