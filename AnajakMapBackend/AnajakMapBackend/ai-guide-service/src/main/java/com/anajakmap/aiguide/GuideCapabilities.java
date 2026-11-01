package com.anajakmap.aiguide;

import java.util.Map;

/** Configuration facts only. Reading capabilities never calls or verifies the AI provider. */
final class GuideCapabilities {
  private GuideCapabilities() {}

  static Map<String, Object> describe(
      String provider, boolean configured, boolean demo, boolean vision, boolean voice) {
    boolean text = configured || demo;
    return Map.ofEntries(
        Map.entry("provider", provider),
        Map.entry("configured", configured),
        Map.entry("demo", demo),
        Map.entry("providerVerified", false),
        Map.entry("chat", text),
        Map.entry("translation", text),
        Map.entry("itinerary", text),
        Map.entry("recommendations", configured && provider.equals("gemini")),
        Map.entry("recap", text),
        Map.entry("vision", configured && vision),
        Map.entry("voice", configured && voice),
        Map.entry("receipt", false),
        Map.entry("reservation", false));
  }
}
