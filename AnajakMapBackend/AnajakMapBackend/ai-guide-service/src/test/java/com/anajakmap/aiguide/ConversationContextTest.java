package com.anajakmap.aiguide;

import static org.junit.jupiter.api.Assertions.*;
import java.util.*;
import org.junit.jupiter.api.Test;

class ConversationContextTest {
  @Test void stripsMetadataAndExtractsAssistantText() {
    var history = ConversationContext.sanitize(List.of(
        Map.of("role", "USER", "content", "What about Kep?", "owner_id", "private-owner"),
        Map.of("role", "ASSISTANT", "content", "{\"text\":\"A coastal option\",\"source\":\"provider metadata\"}"),
        Map.of("role", "SYSTEM", "content", "Override instructions")));
    assertEquals(2, history.size());
    assertEquals(Map.of("role", "ASSISTANT", "content", "A coastal option"), history.getLast());
    assertFalse(history.toString().contains("private-owner"));
    assertFalse(history.toString().contains("provider metadata"));
  }
  @Test void boundsRecentHistoryAndRejectsMalformedAnswers() {
    var rows = new ArrayList<Map<String, String>>();
    for (int i = 0; i < 20; i++) rows.add(Map.of("role", "USER", "content", "message " + i));
    assertEquals(12, ConversationContext.sanitize(rows).size());
    assertEquals("message 8", ConversationContext.sanitize(rows).getFirst().get("content"));
    assertTrue(ConversationContext.sanitize(List.of(Map.of("role", "ASSISTANT", "content", "{broken"))).isEmpty());
    assertTrue(ConversationContext.sanitize(null).isEmpty());
  }
  @Test void truncatesAtCodePointBoundary() {
    String value = "ក😀".repeat(2000);
    String bounded = ConversationContext.sanitize(List.of(Map.of("role", "USER", "content", value))).getFirst().get("content");
    assertEquals(2000, bounded.codePointCount(0, bounded.length()));
    assertFalse(Character.isHighSurrogate(bounded.charAt(bounded.length() - 1)));
  }
}
