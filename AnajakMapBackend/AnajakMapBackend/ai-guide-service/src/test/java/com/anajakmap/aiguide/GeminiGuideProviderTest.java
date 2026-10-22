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
  @Test void missingKeyAndUnsupportedOperationsDoNotCallProvider() {
    var missing=new GeminiGuideProvider("", "gemini-3.8-flash", builder.build());
    assertEquals(503,assertThrows(ResponseStatusException.class,()->missing.perform("chat",Map.of("text","Hello"))).getStatusCode().value());
    assertThrows(ResponseStatusException.class,()->provider.perform("receipt",Map.of())); server.verify();
  }
  @Test void rejectsTruncatedAndBlockedOutput() throws Exception {
    response("{\"text\":\"partial\"}", "MAX_TOKENS");
    assertThrows(IllegalArgumentException.class,()->provider.perform("chat",Map.of("text","Hello")));
  }
  @Test void rejectsEmptyText() throws Exception {
    response("{\"text\":\"\"}", "STOP");
    assertThrows(IllegalArgumentException.class,()->provider.perform("chat",Map.of("text","Hello")));
  }
  @Test void recommendationsRejectInventedOrDuplicatePlaces() throws Exception {
    response("{\"recommendations\":[{\"placeIndex\":99,\"reason\":\"Invented\"}]}","STOP");
    assertThrows(IllegalArgumentException.class,()->provider.recommend(List.of(Map.of("name","Temple","category","temple")),List.of("culture"),"en"));
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
    assertThrows(IllegalArgumentException.class,()->provider.itinerary(trip,Map.of(),places));
  }
  @Test void rejectsOutOfTripDates() throws Exception {
    response("{\"activities\":[{\"placeIndex\":0,\"startsAt\":\"2026-10-14T02:00:00Z\",\"endsAt\":\"2026-10-14T03:00:00Z\"}]}","STOP");
    assertThrows(IllegalArgumentException.class,()->provider.itinerary(trip,Map.of(),places));
  }
}
