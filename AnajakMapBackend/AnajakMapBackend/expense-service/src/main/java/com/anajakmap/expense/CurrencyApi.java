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
  private final BigDecimal khrPerUsd;
  private final String url, key;

  public CurrencyApi(
      Environment e,
      @Value("${CURRENCY_PROVIDER_URL:}") String u,
      @Value("${CURRENCY_PROVIDER_KEY:}") String k) {
    url = u;
    key = k;
    khrPerUsd = new BigDecimal(e.getProperty("APP_KHR_PER_USD", "4000"));
    if (khrPerUsd.signum() <= 0 || khrPerUsd.precision() > 9)
      throw new IllegalArgumentException("Invalid application exchange rate");
  }

  @GetMapping
  public Object convert(
      @RequestParam String from, @RequestParam String to, @RequestParam BigDecimal amount) {
    Currency.getInstance(from);
    Currency.getInstance(to);
    if (amount.signum() < 0 || amount.precision() > 14 || amount.scale() > 2)
      throw new IllegalArgumentException();
    if (from.equals(to) || Set.of("USD","KHR").containsAll(List.of(from,to))) {
      BigDecimal rate = from.equals(to) ? BigDecimal.ONE : to.equals("KHR")
          ? khrPerUsd : BigDecimal.ONE.divide(khrPerUsd, 12, RoundingMode.HALF_UP);
      BigDecimal converted = from.equals(to) ? amount : to.equals("KHR")
          ? amount.multiply(khrPerUsd) : amount.divide(khrPerUsd, 12, RoundingMode.HALF_UP);
      return Map.of(
          "amount",
          converted.setScale(to.equals("KHR") ? 0 : 2, RoundingMode.HALF_UP),
          "rate",
          rate,
          "currency",
          to,
          "source",
          "Fixed application rate; not a live market rate",
          "updatedAt",
          Instant.now(),
          "estimate", true, "mock", false,
          "rateType", "fixed", "appRateKhrPerUsd", khrPerUsd);
    }
    if (url.isBlank() || key.isBlank()) throw new org.springframework.web.server.ResponseStatusException(
        org.springframework.http.HttpStatus.SERVICE_UNAVAILABLE, "A live provider is required for this currency pair");
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
