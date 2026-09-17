package com.example.foodorder.config;

import com.example.foodorder.service.OrderMetrics;
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry;
import io.prometheus.metrics.model.registry.MultiCollector;
import io.prometheus.metrics.model.snapshots.CounterSnapshot;
import io.prometheus.metrics.model.snapshots.CounterSnapshot.CounterDataPointSnapshot;
import io.prometheus.metrics.model.snapshots.Labels;
import io.prometheus.metrics.model.snapshots.MetricSnapshots;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.micrometer.metrics.autoconfigure.MeterRegistryCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Exposes the business counter under the exact Prometheus series name
 * {@code orders_created_total}.
 *
 * <p>Micrometer's Prometheus client (1.x) strips the reserved trailing suffix
 * {@code _created} from counter names, so a normal Micrometer counter would be published as
 * {@code orders_total}. To honour the metric contract expected by Prometheus/Grafana we
 * register a tiny custom collector that reads the count from {@link OrderMetrics} and emits
 * a counter snapshot named {@code orders_created} (the Prometheus client appends the
 * {@code _total} suffix on exposition).
 *
 * <p>A {@link MeterRegistryCustomizer} is used (instead of {@code @ConditionalOnBean}) so the
 * collector is registered exactly when the {@link PrometheusMeterRegistry} is created, without
 * relying on bean-definition ordering. It is a no-op for non-Prometheus registries used in tests.
 *
 * <p>{@link OrderMetrics} is resolved lazily via an {@link ObjectProvider} at scrape time. A
 * direct injection would create a bean cycle (registry -> customizer -> OrderMetrics -> registry).
 */
@Configuration
public class PrometheusBusinessMetricsConfig {

    @Bean
    public MeterRegistryCustomizer<PrometheusMeterRegistry> ordersCreatedTotalCustomizer(
            ObjectProvider<OrderMetrics> orderMetricsProvider) {
        return registry -> registry.getPrometheusRegistry().register(
                ordersCreatedCollector(orderMetricsProvider));
    }

    private static MultiCollector ordersCreatedCollector(ObjectProvider<OrderMetrics> orderMetricsProvider) {
        return new MultiCollector() {
            @Override
            public MetricSnapshots collect() {
                double count = orderMetricsProvider.getObject().ordersCreatedCount();
                CounterSnapshot snapshot = CounterSnapshot.builder()
                        .name("orders_created")
                        .help("Total number of successfully created orders")
                        .dataPoint(CounterDataPointSnapshot.builder()
                                .labels(Labels.EMPTY)
                                .value(count)
                                .build())
                        .build();
                return MetricSnapshots.of(snapshot);
            }
        };
    }
}
