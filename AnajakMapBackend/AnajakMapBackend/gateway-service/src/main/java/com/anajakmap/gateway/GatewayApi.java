package com.anajakmap.gateway;

import com.anajakmap.platform.*;
import jakarta.servlet.http.*;
import java.net.*;
import java.net.http.*;
import java.time.*;
import java.util.*;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

@RestController
public class GatewayApi {
  private final RateLimit rate;
  private final HttpClient http =
      HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build();

  public GatewayApi(RateLimit r) {
    rate = r;
  }

  @RequestMapping("/api/v1/**")
  public ResponseEntity<byte[]> proxy(HttpServletRequest request) throws Exception {
    rate.check(
        "gateway:"
            + Changes.hash(
                request.getUserPrincipal() == null
                    ? request.getRemoteAddr()
                    : request.getUserPrincipal().getName()),
        120,
        60);
    String path = request.getRequestURI();
    String domain = path.substring("/api/v1/".length()).split("/")[0];
    String service =
        switch (domain) {
          case "auth", "profile" -> "identity";
          case "trips" -> "trip";
          case "guide" -> "ai-guide";
          case "discovery" -> "discovery";
          case "expenses" -> "expense";
          case "reservations" -> "reservation";
          case "journal" -> "journal";
          case "notifications" -> "notification";
          default -> throw Api.missing();
        };
    int port =
        switch (service) {
          case "identity" -> 8081;
          case "trip" -> 8082;
          case "ai-guide" -> 8083;
          case "discovery" -> 8084;
          case "expense" -> 8085;
          case "reservation" -> 8086;
          case "journal" -> 8087;
          default -> 8088;
        };
    String base = System.getenv(service.toUpperCase().replace('-', '_') + "_URL");
    if (base == null) base = "http://" + service + "-service:" + port;
    byte[] body = request.getInputStream().readNBytes(11 * 1024 * 1024 + 1);
    if (body.length > 11 * 1024 * 1024) throw new IllegalArgumentException("Request too large");
    var builder =
        java.net.http.HttpRequest.newBuilder(
                URI.create(
                    base
                        + path
                        + (request.getQueryString() == null ? "" : "?" + request.getQueryString())))
            .timeout(Duration.ofSeconds(30));
    for (String h : List.of("Authorization", "Content-Type", "Idempotency-Key", "If-Match")) {
      String v = request.getHeader(h);
      if (v != null) builder.header(h, v);
    }
    String trace = org.slf4j.MDC.get("traceId");
    if (trace != null) builder.header("X-Trace-ID", trace);
    var response =
        http.send(
            builder
                .method(
                    request.getMethod(), java.net.http.HttpRequest.BodyPublishers.ofByteArray(body))
                .build(),
            HttpResponse.BodyHandlers.ofByteArray());
    var out = ResponseEntity.status(response.statusCode()).header("Cache-Control", "no-store");
    response.headers().firstValue("Content-Type").ifPresent(v -> out.header("Content-Type", v));
    response.headers().firstValue("Retry-After").ifPresent(v -> out.header("Retry-After", v));
    return out.body(response.body());
  }
}
