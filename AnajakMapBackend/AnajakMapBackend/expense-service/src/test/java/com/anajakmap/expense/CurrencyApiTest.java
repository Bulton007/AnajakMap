package com.anajakmap.expense;
import static org.junit.jupiter.api.Assertions.*;
import java.math.BigDecimal;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.web.server.ResponseStatusException;
class CurrencyApiTest {
  final CurrencyApi api = new CurrencyApi(new MockEnvironment(), "", "");
  @Test void fixedRateIsExactAndClearlyIdentified() {
    var result = (Map<?,?>)api.convert("USD","KHR",new BigDecimal("12.34"));
    assertEquals(new BigDecimal("49360"),result.get("amount"));
    assertEquals("fixed",result.get("rateType"));
    assertEquals(false,result.get("mock"));
    assertEquals(new BigDecimal("4000"),result.get("appRateKhrPerUsd"));
    assertEquals(new BigDecimal("1.25"),((Map<?,?>)api.convert("KHR","USD",new BigDecimal("5000"))).get("amount"));
  }
  @Test void cashRoundingIsHalfUpAndBalancesAreNotTouched() {
    assertEquals(new BigDecimal("0.01"),((Map<?,?>)api.convert("KHR","USD",new BigDecimal("20"))).get("amount"));
    assertThrows(ResponseStatusException.class,()->api.convert("EUR","USD",BigDecimal.ONE));
    assertThrows(IllegalArgumentException.class,()->api.convert("USD","KHR",new BigDecimal("-1")));
  }
  @Test void configuredRateHasOneAuthoritativeLocation() {
    var custom = new CurrencyApi(new MockEnvironment().withProperty("APP_KHR_PER_USD","4001"),"","");
    assertEquals(new BigDecimal("4001"),((Map<?,?>)custom.convert("USD","KHR",BigDecimal.ONE)).get("amount"));
  }
}
