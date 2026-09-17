package com.example.foodorder.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.example.foodorder.domain.Order;
import com.example.foodorder.domain.Product;
import com.example.foodorder.repository.OrderRepository;
import com.example.foodorder.repository.ProductRepository;
import com.example.foodorder.web.dto.CreateOrderRequest;
import com.example.foodorder.web.dto.OrderItemRequest;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import io.micrometer.observation.Observation;
import io.micrometer.observation.ObservationRegistry;
import io.micrometer.tracing.handler.DefaultTracingObservationHandler;
import io.micrometer.tracing.otel.bridge.OtelCurrentTraceContext;
import io.micrometer.tracing.otel.bridge.OtelTracer;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.testing.exporter.InMemorySpanExporter;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.data.SpanData;
import io.opentelemetry.sdk.trace.export.SimpleSpanProcessor;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * Test type 3 - Trace unit test using the OpenTelemetry SDK in-process (NO OTel agent).
 *
 * <p>An {@link ObservationRegistry} is bridged to a real OTel {@code SdkTracerProvider} via
 * {@code micrometer-tracing-bridge-otel}; finished spans are captured by an
 * {@link InMemorySpanExporter}. Asserts that the production {@code orders.create} observation
 * becomes a child span (correct name, business attributes, parent-child relationship).
 */
@ExtendWith(MockitoExtension.class)
class OrderTracingTest {

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private ProductRepository productRepository;

    private OpenTelemetrySdk otelSdk;
    private InMemorySpanExporter spanExporter;
    private ObservationRegistry observationRegistry;
    private OrderService orderService;

    private final Product pizza = new Product("Pizza Margherita", "Classic", 899, "Food");
    private final Product water = new Product("Sparkling Water", "0.5l", 150, "Drinks");

    @BeforeEach
    void setUp() {
        spanExporter = InMemorySpanExporter.create();
        SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
                .addSpanProcessor(SimpleSpanProcessor.create(spanExporter))
                .build();
        otelSdk = OpenTelemetrySdk.builder().setTracerProvider(tracerProvider).build();

        OtelTracer micrometerTracer = new OtelTracer(
                otelSdk.getTracer("food-order-test"),
                new OtelCurrentTraceContext(),
                event -> {
                });

        observationRegistry = ObservationRegistry.create();
        observationRegistry.observationConfig()
                .observationHandler(new DefaultTracingObservationHandler(micrometerTracer));

        OrderMetrics orderMetrics = new OrderMetrics(new SimpleMeterRegistry());
        orderService = new OrderService(orderRepository, productRepository, orderMetrics,
                observationRegistry);
    }

    @AfterEach
    void tearDown() {
        otelSdk.close();
    }

    @Test
    @DisplayName("produces an 'orders.create' child span with business attributes")
    void producesOrdersCreateSpan() {
        when(orderRepository.save(any(Order.class))).thenAnswer(inv -> inv.getArgument(0));
        when(productRepository.findById(1L)).thenReturn(Optional.of(pizza));
        when(productRepository.findById(2L)).thenReturn(Optional.of(water));
        CreateOrderRequest request = new CreateOrderRequest("Ada", List.of(
                new OrderItemRequest(1L, 2),   // 2 line items -> item_count=2
                new OrderItemRequest(2L, 3)));  // total 2x899 + 3x150 = 2248 cents

        // Run the production observation inside a parent span to assert parent-child linkage.
        Observation.createNotStarted("test.parent", observationRegistry)
                .observe(() -> orderService.createOrder(request));

        List<SpanData> spans = spanExporter.getFinishedSpanItems();
        assertThat(spans).hasSize(2);

        SpanData parentSpan = spanNamed(spans, "test.parent");
        SpanData orderSpan = spanNamed(spans, "orders.create");

        assertThat(orderSpan.getParentSpanContext().getSpanId()).isEqualTo(parentSpan.getSpanId());
        assertThat(orderSpan.getTraceId()).isEqualTo(parentSpan.getTraceId());
        assertThat(orderSpan.getAttributes().get(AttributeKey.stringKey("order.item_count")))
                .isEqualTo("2");
        assertThat(orderSpan.getAttributes().get(AttributeKey.stringKey("order.value_cents")))
                .isEqualTo("2248");
    }

    private static SpanData spanNamed(List<SpanData> spans, String name) {
        return spans.stream()
                .filter(s -> s.getName().equals(name))
                .findFirst()
                .orElseThrow(() -> new AssertionError("No span named '" + name + "' in " + spans));
    }
}
