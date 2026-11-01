package com.anajakmap.aiguide;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

class GeminiGuideProviderTest {
  RestClient.Builder builder = RestClient.builder().baseUrl("https://generativelanguage.googleapis.com");
  MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
  GeminiGuideProvider provider = new GeminiGuideProvider("test-key", "gemini-3.8-flash", builder.build());
  void response(String text, String finish) throws Exception {
    server.expect(requestTo("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent"))
        .andExpect(header("x-goog-api-key", "test-key"))
        .andRespond(withSuccess(new ObjectMapper().writeValueAsString(Map.of("candidates", List.of(Map.of(
            "finishReason", finish, "content", Map.of("parts", List.of(Map.of("text", text))))))), MediaType.APPLICATION_JSON));
  }
  @Test void chatUsesRealContractAndMarksNonMock() throws Exception {
    response("{\"text\":\"សួស្តី\"}", "STOP");
    var result=provider.perform("chat", Map.of("text", "Hello"));
    assertEquals("សួស្តី",result.get("text")); assertEquals(false,result.get("mock")); server.verify();
  }
  @Test void configuredThinkingModelUsesLowThinkingForMobileLatency() throws Exception {
    server.expect(anything())
        .andExpect(content().json("{\"generationConfig\":{\"thinkingConfig\":{\"thinkingLevel\":\"LOW\"}}}", false))
        .andRespond(withSuccess("{\"candidates\":[{\"finishReason\":\"STOP\",\"content\":{\"parts\":[{\"text\":\"{\\\"text\\\":\\\"Hello\\\"}\"}]}}]}", MediaType.APPLICATION_JSON));
    assertEquals("Hello", provider.perform("chat", Map.of("text", "Hello")).get("text"));
    server.verify();
  }
  @Test void optedInContextContainsOnlyBoundedConversationText() throws Exception {
    server.expect(anything())
        .andExpect(content().string(org.hamcrest.Matchers.containsString("earlier coast question")))
        .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("private-owner-id"))))
        .andRespond(withSuccess("{\"candidates\":[{\"finishReason\":\"STOP\",\"content\":{\"parts\":[{\"text\":\"{\\\"text\\\":\\\"Follow-up answer\\\"}\"}]}}]}", MediaType.APPLICATION_JSON));
    var result = provider.perform("chat", Map.of("text", "And tomorrow?", "history", List.of(
        Map.of("role", "USER", "content", "earlier coast question", "owner_id", "private-owner-id"))));
    assertEquals("Follow-up answer", result.get("text"));
    server.verify();
  }
  @Test void missingKeyAndUnsupportedOperationsDoNotCallProvider() {
    var missing=new GeminiGuideProvider("", "gemini-3.8-flash", builder.build());
    assertEquals(503,assertThrows(ResponseStatusException.class,()->missing.perform("chat",Map.of("text","Hello"))).getStatusCode().value());
    assertFalse((Boolean)provider.capabilities().get("receipt"));
    assertFalse((Boolean)provider.capabilities().get("reservation"));
    assertThrows(ResponseStatusException.class,()->provider.perform("receipt",Map.of())); server.verify();
  }
  @Test void rejectsTruncatedAndBlockedOutput() throws Exception {
    response("{\"text\":\"partial\"}", "MAX_TOKENS");
    assertEquals(502, assertThrows(ResponseStatusException.class,()->provider.perform("chat",Map.of("text","Hello"))).getStatusCode().value());
  }
  @Test void rejectsEmptyText() throws Exception {
    response("{\"text\":\"\"}", "STOP");
    assertEquals(502, assertThrows(ResponseStatusException.class,()->provider.perform("chat",Map.of("text","Hello"))).getStatusCode().value());
  }
  @Test void malformedProviderJsonIsAProviderFailureWithoutLeakingTheReply() throws Exception {
    response("private-provider-reply-is-not-json", "STOP");
    var failure = assertThrows(ResponseStatusException.class, () -> provider.perform("chat", Map.of("text", "Hello")));
    assertEquals(502, failure.getStatusCode().value());
    assertFalse(failure.getMessage().contains("private-provider-reply"));
    assertNull(failure.getCause());
    server.verify();
  }
  @Test void invalidUserTextStillFailsBeforeAnyProviderCall() {
    assertThrows(IllegalArgumentException.class, () -> provider.perform("chat", Map.of("text", "")));
    server.verify();
  }
  @Test void khmerTranslationUsesExplicitLanguageInstructionAndAcceptsKhmer() throws Exception {
    server.expect(anything())
        .andExpect(content().string(org.hamcrest.Matchers.containsString("Khmer (Cambodian)")))
        .andExpect(content().string(org.hamcrest.Matchers.containsString("never Thai script")))
        .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("Reply in the user's language"))))
        .andRespond(withSuccess("{\"candidates\":[{\"finishReason\":\"STOP\",\"content\":{\"parts\":[{\"text\":\"{\\\"text\\\":\\\"សូមស្វាគមន៍មកកាន់កោះស្រមើស្រមៃរបស់យើង។\\\"}\"}]}}]}", MediaType.APPLICATION_JSON));
    var result = provider.perform("translation", Map.of("text", "Welcome to our imaginary island.", "targetLanguage", "km"));
    assertEquals("km", result.get("targetLanguage"));
    assertEquals("សូមស្វាគមន៍មកកាន់កោះស្រមើស្រមៃរបស់យើង។", result.get("text"));
    server.verify();
  }
  @Test void rejectsThaiTranslationForKhmerAsProviderFailure() throws Exception {
    response("{\"text\":\"ยินดีต้อนรับสู่เกาะจินตนาการของเรา\"}", "STOP");
    response("{\"text\":\"ยินดีต้อนรับสู่เกาะจินตนาการของเรา\"}", "STOP");
    var failure = assertThrows(ResponseStatusException.class, () -> provider.perform("translation", Map.of("text", "Welcome to our imaginary island.", "targetLanguage", "km")));
    assertEquals(502, failure.getStatusCode().value());
    assertFalse(failure.getReason().contains("ยินดี"));
    server.verify();
  }
  @Test void rejectsMixedThaiAndKhmerRatherThanAcceptingOneKhmerCharacter() throws Exception {
    response("{\"text\":\"សួស្តី ยินดีต้อนรับ\"}", "STOP");
    response("{\"text\":\"សួស្តី ยินดีต้อนรับ\"}", "STOP");
    assertEquals(502, assertThrows(ResponseStatusException.class, () -> provider.perform("translation", Map.of("text", "Hello", "targetLanguage", "km"))).getStatusCode().value());
    server.verify();
  }
  @Test void correctsOneGeorgianContaminatedReplyWithoutSharingThatReply() throws Exception {
    response("{\"text\":\"សូមស្វាគមន៍មកកាន់កោះ წარមៃរបស់យើង។\"}", "STOP");
    server.expect(anything())
        .andExpect(content().string(org.hamcrest.Matchers.containsString("Translation quality check")))
        .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("წარ"))))
        .andRespond(withSuccess("{\"candidates\":[{\"finishReason\":\"STOP\",\"content\":{\"parts\":[{\"text\":\"{\\\"text\\\":\\\"អរគុណ។\\\"}\"}]}}]}", MediaType.APPLICATION_JSON));
    assertEquals("អរគុណ។", provider.perform("translation", Map.of("text", "Thank you.", "targetLanguage", "km")).get("text"));
    server.verify();
  }
  @Test void twoForeignScriptRepliesFailWithoutAThirdProviderRequest() throws Exception {
    response("{\"text\":\"សួស្តី წარ\"}", "STOP");
    response("{\"text\":\"សួស្តី مرحبا\"}", "STOP");
    assertEquals(502, assertThrows(ResponseStatusException.class, () -> provider.perform("translation", Map.of("text", "Hello", "targetLanguage", "km"))).getStatusCode().value());
    server.verify();
  }
  @Test void khmerCanRetainLatinProperNamesPunctuationAndCombiningMarks() throws Exception {
    response("{\"text\":\"សូមស្វាគមន៍មកកាន់ Siem Reap និង Café!\"}", "STOP");
    assertEquals("សូមស្វាគមន៍មកកាន់ Siem Reap និង Café!", provider.perform("translation", Map.of("text", "Welcome to Siem Reap and Café!", "targetLanguage", "km")).get("text"));
    server.verify();
  }
  @Test void targetLanguageNormalizationCannotBypassKhmerValidation() throws Exception {
    response("{\"text\":\"Welcome\"}", "STOP");
    response("{\"text\":\"Welcome\"}", "STOP");
    assertEquals(502, assertThrows(ResponseStatusException.class, () -> provider.perform("translation", Map.of("text", "Hello", "targetLanguage", " KM "))).getStatusCode().value());
    server.verify();
  }
  @Test void englishTranslationContractIsUnchanged() throws Exception {
    response("{\"text\":\"Welcome\"}", "STOP");
    var result=provider.perform("translation", Map.of("text", "សូមស្វាគមន៍", "targetLanguage", "en"));
    assertEquals("en", result.get("targetLanguage"));
    assertEquals("Welcome", result.get("text"));
    server.verify();
  }
  @Test void recommendationsRejectInventedOrDuplicatePlaces() throws Exception {
    response("{\"recommendations\":[{\"placeIndex\":99,\"reason\":\"Invented\"}]}","STOP");
    assertEquals(502, assertThrows(ResponseStatusException.class,()->provider.recommend(List.of(Map.of("name","Temple","category","temple")),List.of("culture"),"en")).getStatusCode().value());
  }
  @Test void sanitizesProviderErrors() {
    server.expect(anything()).andRespond(withStatus(org.springframework.http.HttpStatus.TOO_MANY_REQUESTS).body("private provider body"));
    var error=assertThrows(ResponseStatusException.class,()->provider.perform("chat",Map.of("text","Hello")));
    assertEquals(429,error.getStatusCode().value()); assertFalse(error.getMessage().contains("private provider body"));
  }
  Map<String,Object> trip=Map.of("startDate","2026-10-12","endDate","2026-10-12","timezone","Asia/Phnom_Penh","destination","Siem Reap");
  List<Map<String,Object>> places=List.of(Map.of("name","Supplied temple","latitude",13.4,"longitude",103.8,"source","development fixture"));
  @Test void itineraryUsesTrustedCoordinatesAndSources() throws Exception {
    response("{\"activities\":[{\"placeIndex\":0,\"startsAt\":\"2026-10-12T02:00:00Z\",\"endsAt\":\"2026-10-12T03:00:00Z\"}]}","STOP");
    var result=provider.itinerary(trip,Map.of(),places);
    assertEquals(13.4,result.activities().getFirst().latitude());
    assertEquals("development fixture",result.activities().getFirst().source()); assertTrue(result.estimate());
  }
  @Test void rejectsInventedPlace() throws Exception {
    response("{\"activities\":[{\"placeIndex\":8}]}","STOP");
    assertEquals(502, assertThrows(ResponseStatusException.class,()->provider.itinerary(trip,Map.of(),places)).getStatusCode().value());
  }
  @Test void rejectsOutOfTripDates() throws Exception {
    response("{\"activities\":[{\"placeIndex\":0,\"startsAt\":\"2026-10-14T02:00:00Z\",\"endsAt\":\"2026-10-14T03:00:00Z\"}]}","STOP");
    assertEquals(502, assertThrows(ResponseStatusException.class,()->provider.itinerary(trip,Map.of(),places)).getStatusCode().value());
  }
  @Test void malformedProviderTimestampIsAProviderFailure() throws Exception {
    response("{\"activities\":[{\"placeIndex\":0,\"startsAt\":\"not-a-date\",\"endsAt\":\"2026-10-12T03:00:00Z\"}]}","STOP");
    var failure = assertThrows(ResponseStatusException.class, () -> provider.itinerary(trip, Map.of(), places));
    assertEquals(502, failure.getStatusCode().value());
    assertFalse(failure.getMessage().contains("not-a-date"));
    server.verify();
  }
  @Test void replanningKeepsCalendarPrivateAndFitsStopsOnBackend() throws Exception {
    server.expect(anything())
        .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("private meeting"))))
        .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("approvedCalendar"))))
        .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("currentWeather"))))
        .andRespond(withSuccess("{\"candidates\":[{\"finishReason\":\"STOP\",\"content\":{\"parts\":[{\"text\":\"{\\\"activities\\\":[{\\\"placeIndex\\\":0,\\\"startsAt\\\":\\\"2026-10-12T02:00:00Z\\\",\\\"endsAt\\\":\\\"2026-10-12T03:00:00Z\\\"}]}\"}]}}]}", MediaType.APPLICATION_JSON));
    var result = provider.itinerary(trip, Map.of("approvedCalendar", Map.of("events", List.of(
        Map.of("title", "private meeting", "STARTS_AT", "2026-10-12T02:30:00Z", "ENDS_AT", "2026-10-12T03:30:00Z"))),
        "currentWeather", Map.of("privateMetadata", "not sent")), places);
    assertEquals(java.time.Instant.parse("2026-10-12T03:30:00Z"), result.activities().getFirst().startsAt());
    assertEquals(java.time.Instant.parse("2026-10-12T04:30:00Z"), result.activities().getFirst().endsAt());
    server.verify();
  }
}
