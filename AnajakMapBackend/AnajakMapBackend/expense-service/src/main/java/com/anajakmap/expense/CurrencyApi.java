package com.anajakmap.expense;

import com.anajakmap.platform.*;
import java.math.*;
import java.time.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/expenses/currency")
public class CurrencyApi {
  private final boolean dev;
  private final String url, key;

  public CurrencyApi(
      Environment e,
      @Value("${CURRENCY_PROVIDER_URL:}") String u,
      @Value("${CURRENCY_PROVIDER_KEY:}") String k) {
    url = u;
    key = k;
    dev =
        Arrays.asList(e.getActiveProfiles()).stream()
            .anyMatch(p -> p.equals("dev") || p.equals("test"));
    if (!dev && (u.isBlank() || k.isBlank()))
      throw new IllegalStateException("Currency provider URL/key required outside dev/test");
  }

  @GetMapping
  public Object convert(
      @RequestParam String from, @RequestParam String to, @RequestParam BigDecimal amount) {
    Currency.getInstance(from);
    Currency.getInstance(to);
    if (amount.signum() < 0 || amount.precision() > 14 || amount.scale() > 2)
      throw new IllegalArgumentException();
    if (dev) {
      Map<String, BigDecimal> rates =
          Map.of(
              "USD", BigDecimal.ONE, "KHR", new BigDecimal("4100"), "EUR", new BigDecimal("0.90"));
      if (!rates.containsKey(from) || !rates.containsKey(to))
        throw new IllegalArgumentException("Dev supports USD/KHR/EUR");
      BigDecimal rate = rates.get(to).divide(rates.get(from), 10, RoundingMode.HALF_EVEN);
      return Map.of(
          "amount",
          amount.multiply(rate).setScale(2, RoundingMode.HALF_EVEN),
          "rate",
          rate,
          "currency",
          to,
          "source",
          "development fixture",
          "updatedAt",
          Instant.now(),
          "estimate",
          true,
          "mock",
          true);
    }
    Map result =
        HttpClients.client(url)
            .post()
            .uri("/currency")
            .header("Authorization", "Bearer " + key)
            .body(Map.of("from", from, "to", to, "amount", amount))
            .retrieve()
            .body(Map.class);
    if (result == null
        || !result.containsKey("rate")
        || !result.containsKey("source")
        || !result.containsKey("updatedAt"))
      throw new IllegalArgumentException("Invalid currency response");
    return result;
  }
}
