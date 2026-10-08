package com.anajakmap.aiguide;

import java.math.BigDecimal;
import java.util.*;

public final class GuideResponseValidation {
  private GuideResponseValidation() {}

  public static void validate(String operation, Map<String, Object> result) {
    if (result == null) throw new IllegalArgumentException("Missing AI response");
    switch (operation) {
      case "translation", "recap", "chat" -> text(result, "text");
      case "vision" -> {
        if (!(result.get("possibleLandmarks") instanceof List<?> list))
          throw new IllegalArgumentException("Missing recognition candidates");
        text(result, "explanation");
        if (!(result.get("extractedText") instanceof String))
          throw new IllegalArgumentException("Missing extracted text");
        for (Object item : list) {
          if (!(item instanceof Map<?, ?> candidate)
              || !(candidate.get("name") instanceof String)
              || !(candidate.get("confidence") instanceof Number n)
              || !Double.isFinite(n.doubleValue())
              || n.doubleValue() < 0
              || n.doubleValue() > 1)
            throw new IllegalArgumentException("Invalid recognition candidate");
        }
      }
      case "receipt" -> {
        BigDecimal amount = new BigDecimal(Objects.toString(result.get("amount"), ""));
        if (amount.signum() < 0 || amount.precision() > 14 || amount.scale() > 2)
          throw new IllegalArgumentException("Invalid receipt amount");
        Currency.getInstance(Objects.toString(result.get("currency"), ""));
      }
      case "reservation" -> text(result, "provider");
      case "voice" -> {
        if (!(result.get("transcript") instanceof String)
            && !(result.get("audioBase64") instanceof String))
          throw new IllegalArgumentException("Missing voice output");
      }
      default -> throw new IllegalArgumentException("Unknown operation");
    }
  }

  private static void text(Map<String, Object> r, String key) {
    if (!(r.get(key) instanceof String s) || s.isBlank() || s.length() > 16000)
      throw new IllegalArgumentException("Invalid AI text");
  }
}
