package com.anajakmap.aiguide;

import static org.junit.jupiter.api.Assertions.*;

import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class GuideCapabilitiesTest {
  private RestClient noNetworkClient() {
    var builder = RestClient.builder();
    MockRestServiceServer.bindTo(builder).build();
    return builder.build();
  }

  @Test void missingGeminiKeyDisablesEveryLiveFeatureEvenWhenMediaFlagsAreTrue() {
    var provider = new GeminiGuideProvider("", "gemini-test", noNetworkClient(), true, true);
    var result = provider.capabilities();
    assertEquals("gemini", result.get("provider"));
    for (String field : new String[]{"configured", "demo", "providerVerified", "chat", "translation",
        "itinerary", "recommendations", "recap", "vision", "voice", "receipt", "reservation"})
      assertEquals(false, result.get(field), field);
  }

  @Test void keyPresenceDoesNotClaimProviderWasVerifiedOrEnableUnconfiguredMedia() {
    var result = new GeminiGuideProvider("synthetic-key", "gemini-test", noNetworkClient()).capabilities();
    assertEquals(true, result.get("configured"));
    for (String field : new String[]{"chat", "translation", "itinerary", "recommendations", "recap"})
      assertEquals(true, result.get(field), field);
    for (String field : new String[]{"providerVerified", "demo", "vision", "voice", "receipt", "reservation"})
      assertEquals(false, result.get(field), field);
    assertFalse(result.toString().contains("synthetic-key"));
  }

  @Test void explicitMediaFlagsEnableOnlyTheirRespectiveOperations() {
    var result = new GeminiGuideProvider("synthetic-key", "gemini-test", noNetworkClient(), true, false).capabilities();
    assertEquals(true, result.get("vision"));
    assertEquals(false, result.get("voice"));
    assertEquals(false, result.get("providerVerified"));
  }

  @Test void fixtureIsIdentifiableAsDemoAndHasNoProviderRecommendationOrMedia() {
    Map<String, Object> result = new GuideAdapters().mock().capabilities();
    assertEquals("fixture", result.get("provider"));
    assertEquals(true, result.get("demo"));
    assertEquals(false, result.get("configured"));
    assertEquals(true, result.get("chat"));
    assertEquals(false, result.get("recommendations"));
    assertEquals(false, result.get("vision"));
    assertEquals(false, result.get("voice"));
    assertEquals(false, result.get("providerVerified"));
  }

  @Test void everyFixtureAnswerCarriesAnExplicitDemoSource() {
    var provider = new GuideAdapters().mock();
    for (String operation : new String[]{"chat", "translation", "recap", "vision", "voice", "receipt", "reservation"}) {
      var answer = provider.perform(operation, Map.of("text", "Fictional question"));
      assertEquals(true, answer.get("mock"), operation);
      assertEquals("Development fixture", answer.get("source"), operation);
    }
  }
}
