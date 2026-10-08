package com.anajakmap.platform;

import java.time.Instant;
import org.slf4j.MDC;
import org.springframework.dao.*;
import org.springframework.http.*;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestControllerAdvice
public class Api {
  public record Error(String code, String message, String traceId, Instant timestamp) {}

  @ExceptionHandler(ResponseStatusException.class)
  ResponseEntity<Error> domain(ResponseStatusException e) {
    return ResponseEntity.status(e.getStatusCode())
        .headers(e.getHeaders())
        .body(
            new Error(
                e.getStatusCode().toString(), e.getReason(), MDC.get("traceId"), Instant.now()));
  }

  @ExceptionHandler({
    MethodArgumentNotValidException.class,
    IllegalArgumentException.class,
    org.springframework.http.converter.HttpMessageNotReadableException.class
  })
  ResponseEntity<Error> bad(Exception e) {
    return ResponseEntity.badRequest()
        .body(new Error("VALIDATION", "Invalid request", MDC.get("traceId"), Instant.now()));
  }

  @ExceptionHandler({
    OptimisticLockingFailureException.class,
    DataIntegrityViolationException.class
  })
  ResponseEntity<Error> conflict(Exception e) {
    return ResponseEntity.status(409)
        .body(
            new Error(
                "CONFLICT",
                "Concurrent edit or duplicate record",
                MDC.get("traceId"),
                Instant.now()));
  }

  @ExceptionHandler({
    org.springframework.web.client.ResourceAccessException.class,
    java.net.ConnectException.class,
    java.net.http.HttpTimeoutException.class
  })
  ResponseEntity<Error> unavailable(Exception e) {
    return ResponseEntity.status(503)
        .body(
            new Error(
                "UNAVAILABLE",
                "Provider or downstream service unavailable",
                MDC.get("traceId"),
                Instant.now()));
  }

  @ExceptionHandler(org.springframework.web.client.HttpClientErrorException.class)
  ResponseEntity<Error> downstream(org.springframework.web.client.HttpClientErrorException e) {
    return ResponseEntity.status(e.getStatusCode())
        .body(
            new Error(
                "DOWNSTREAM",
                e.getStatusCode().is4xxClientError()
                    ? "Downstream request rejected"
                    : "Provider failed",
                MDC.get("traceId"),
                Instant.now()));
  }

  @ExceptionHandler(org.springframework.web.client.HttpServerErrorException.class)
  ResponseEntity<Error> provider(Exception e) {
    return ResponseEntity.status(502)
        .body(new Error("PROVIDER_FAILURE", "Provider failed", MDC.get("traceId"), Instant.now()));
  }

  @ExceptionHandler(org.springframework.dao.EmptyResultDataAccessException.class)
  ResponseEntity<Error> absent(Exception e) {
    return ResponseEntity.status(404)
        .body(new Error("NOT_FOUND", "Record not found", MDC.get("traceId"), Instant.now()));
  }

  @ExceptionHandler(Exception.class)
  ResponseEntity<Error> unknown(Exception e) {
    org.slf4j.LoggerFactory.getLogger(Api.class)
        .error("request_failed type={}", e.getClass().getSimpleName());
    return ResponseEntity.status(500)
        .body(new Error("INTERNAL", "Request failed", MDC.get("traceId"), Instant.now()));
  }

  public static ResponseStatusException denied() {
    return new ResponseStatusException(HttpStatus.FORBIDDEN, "Resource access denied");
  }

  public static ResponseStatusException missing() {
    return new ResponseStatusException(HttpStatus.NOT_FOUND, "Record not found");
  }

  public static ResponseStatusException conflict() {
    return new ResponseStatusException(HttpStatus.CONFLICT, "Version or state conflict");
  }
}
