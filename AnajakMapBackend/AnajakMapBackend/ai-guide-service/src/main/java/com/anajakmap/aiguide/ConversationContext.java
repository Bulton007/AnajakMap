package com.anajakmap.aiguide;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.*;

/** Bounded text context: excludes database identifiers and provider metadata. */
final class ConversationContext {
  private static final ObjectMapper JSON = new ObjectMapper();
  private ConversationContext() {}

  static List<Map<String, String>> sanitize(Object value) {
    if (!(value instanceof List<?> rows)) return List.of();
    var output = new ArrayList<Map<String, String>>();
    for (Object item : rows.subList(Math.max(0, rows.size() - 12), rows.size())) {
      if (!(item instanceof Map<?, ?> row)) continue;
      String role = Objects.toString(row.get("role"), "");
      if (!Set.of("USER", "ASSISTANT").contains(role)) continue;
      String text = Objects.toString(row.get("content"), "");
      if (role.equals("ASSISTANT") && text.stripLeading().startsWith("{")) {
        try { text = JSON.readTree(text).path("text").asText(""); }
        catch (Exception invalid) { continue; }
      }
      if (text.isBlank()) continue;
      int end = text.offsetByCodePoints(0, Math.min(text.codePointCount(0, text.length()), 2000));
      output.add(Map.of("role", role, "content", text.substring(0, end)));
    }
    return output;
  }
}
