package com.example.foodorder.web.dto;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;
import java.util.List;
import java.util.stream.Stream;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

/**
 * Verifies the request-level bean-validation constraints that guard the POST /api/orders
 * endpoint before the service is ever invoked.
 */
class CreateOrderRequestValidationTest {

    private static ValidatorFactory factory;
    private static Validator validator;

    @BeforeAll
    static void initValidator() {
        factory = Validation.buildDefaultValidatorFactory();
        validator = factory.getValidator();
    }

    @AfterAll
    static void closeValidator() {
        factory.close();
    }

    @Test
    @DisplayName("accepts a well-formed request")
    void acceptsValidRequest() {
        CreateOrderRequest request = new CreateOrderRequest(
                "Ada", List.of(new OrderItemRequest(1L, 2)));

        assertThat(validator.validate(request)).isEmpty();
    }

    static Stream<Arguments> invalidRequests() {
        List<OrderItemRequest> oneItem = List.of(new OrderItemRequest(1L, 1));
        return Stream.of(
                Arguments.of("blank customer name",
                        new CreateOrderRequest("  ", oneItem), "customerName"),
                Arguments.of("missing customer name",
                        new CreateOrderRequest(null, oneItem), "customerName"),
                Arguments.of("empty item list",
                        new CreateOrderRequest("Ada", List.of()), "items"),
                Arguments.of("missing item list",
                        new CreateOrderRequest("Ada", null), "items"),
                Arguments.of("missing product id",
                        new CreateOrderRequest("Ada", List.of(new OrderItemRequest(null, 1))),
                        "items[0].productId"),
                Arguments.of("zero quantity",
                        new CreateOrderRequest("Ada", List.of(new OrderItemRequest(1L, 0))),
                        "items[0].quantity"),
                Arguments.of("negative quantity",
                        new CreateOrderRequest("Ada", List.of(new OrderItemRequest(1L, -1))),
                        "items[0].quantity"));
    }

    @ParameterizedTest(name = "rejects {0}")
    @MethodSource("invalidRequests")
    void rejectsInvalidRequest(String description, CreateOrderRequest request, String expectedPath) {
        assertThat(validator.validate(request))
                .extracting(ConstraintViolation::getPropertyPath)
                .map(Object::toString)
                .containsExactly(expectedPath);
    }
}