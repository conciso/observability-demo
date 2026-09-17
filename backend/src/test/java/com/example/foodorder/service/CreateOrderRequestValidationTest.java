package com.example.foodorder.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.foodorder.web.dto.CreateOrderRequest;
import com.example.foodorder.web.dto.OrderItemRequest;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

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

    @Test
    @DisplayName("rejects a blank customer name")
    void rejectsBlankCustomerName() {
        CreateOrderRequest request = new CreateOrderRequest(
                "  ", List.of(new OrderItemRequest(1L, 1)));

        Set<ConstraintViolation<CreateOrderRequest>> violations = validator.validate(request);

        assertThat(violations).anyMatch(v -> v.getPropertyPath().toString().equals("customerName"));
    }

    @Test
    @DisplayName("rejects an empty item list")
    void rejectsEmptyItems() {
        CreateOrderRequest request = new CreateOrderRequest("Ada", List.of());

        Set<ConstraintViolation<CreateOrderRequest>> violations = validator.validate(request);

        assertThat(violations).anyMatch(v -> v.getPropertyPath().toString().equals("items"));
    }

    @Test
    @DisplayName("rejects a non-positive quantity")
    void rejectsNonPositiveQuantity() {
        CreateOrderRequest request = new CreateOrderRequest(
                "Ada", List.of(new OrderItemRequest(1L, 0)));

        Set<ConstraintViolation<CreateOrderRequest>> violations = validator.validate(request);

        assertThat(violations).anyMatch(v -> v.getPropertyPath().toString().contains("quantity"));
    }
}
