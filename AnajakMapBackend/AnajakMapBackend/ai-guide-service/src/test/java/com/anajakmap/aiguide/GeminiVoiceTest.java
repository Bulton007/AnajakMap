package com.anajakmap.aiguide;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.http.*;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

class GeminiVoiceTest {
  RestClient.Builder builder = RestClient.builder().baseUrl("https://generativelanguage.googleapis.com");
  MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
  GeminiGuideProvider enabled = new GeminiGuideProvider("test-key", "gemini-test", builder.build(), true, true);
  Map<String,Object> input() {
    return new HashMap<>(Map.of("shareWithProvider", true, "mimeType", "audio/wav", "language", "en",
        "audioBase64", Base64.getEncoder().encodeToString(VoiceAudioTest.wave(1))));
  }
  String response(String text) throws Exception {
    return new ObjectMapper().writeValueAsString(Map.of("candidates", List.of(Map.of(
        "finishReason", "STOP", "content", Map.of("parts", List.of(Map.of("text", text)))))));
  }
  @Test void disabledMissingKeyOrConsentNeverCallsGoogle() {
    var disabled = new GeminiGuideProvider("test-key", "gemini-test", builder.build());
    assertEquals(false, disabled.capabilities().get("voice"));
    assertThrows(ResponseStatusException.class, () -> disabled.perform("voice", input()));
    var missing = new GeminiGuideProvider("", "gemini-test", builder.build(), true, true);
    assertEquals(false, missing.capabilities().get("voice"));
    assertThrows(ResponseStatusException.class, () -> missing.perform("voice", input()));
    var data = input(); data.remove("shareWithProvider");
    assertThrows(IllegalArgumentException.class, () -> enabled.perform("voice", data));
    server.verify();
  }
  @Test void validatesRecordingBeforeGoogle() {
    var data = input(); data.put("mimeType", "image/png");
    assertThrows(IllegalArgumentException.class, () -> enabled.perform("voice", data));
    data.put("mimeType", "audio/wav"); data.put("audioBase64", "AAAA");
    assertThrows(IllegalArgumentException.class, () -> enabled.perform("voice", data));
    data.put("audioBase64", "A".repeat(5600001));
    assertThrows(IllegalArgumentException.class, () -> enabled.perform("voice", data));
    server.verify();
  }
  @Test void sendsOnlyConsentedAudioAndLanguageThenReturnsTranscriptAndAnswer() throws Exception {
    server.expect(anything()).andExpect(header("x-goog-api-key", "test-key"))
        .andExpect(content().string(containsString("inlineData")))
        .andExpect(content().string(containsString("audio/wav")))
        .andExpect(content().string(not(containsString("private-owner"))))
        .andExpect(content().string(not(containsString("unapproved-context"))))
        .andRespond(withSuccess(response("{\"transcript\":\"Quiet places?\",\"text\":\"Consider a riverside walk.\",\"speechDetected\":true}"), MediaType.APPLICATION_JSON));
    var data = input(); data.put("ownerId", "private-owner"); data.put("history", "unapproved-context");
    var result = enabled.perform("voice", data);
    assertEquals("Quiet places?", result.get("transcript"));
    assertEquals("Consider a riverside walk.", result.get("text"));
    assertEquals(false, result.get("mock"));
    assertEquals(true, result.get("requiresVerification"));
    server.verify();
  }
  @Test void silenceIsRecoverableRatherThanAReportedSuccess() throws Exception {
    server.expect(anything()).andRespond(withSuccess(response("{\"transcript\":\"\",\"text\":\"Try again.\",\"speechDetected\":false}"), MediaType.APPLICATION_JSON));
    assertEquals(422, assertThrows(ResponseStatusException.class, () -> enabled.perform("voice", input())).getStatusCode().value());
    server.verify();
  }
  @Test void emptyTranscriptIsRejected() throws Exception {
    server.expect(anything()).andRespond(withSuccess(response("{\"transcript\":\"\",\"text\":\"Answer\",\"speechDetected\":true}"), MediaType.APPLICATION_JSON));
    assertEquals(502, assertThrows(ResponseStatusException.class, () -> enabled.perform("voice", input())).getStatusCode().value());
    server.verify();
  }
  @Test void providerRateLimitKeepsServerRetryTiming() {
    server.expect(anything()).andRespond(withStatus(HttpStatus.TOO_MANY_REQUESTS).header("Retry-After", "17"));
    var failure = assertThrows(ResponseStatusException.class, () -> enabled.perform("voice", input()));
    assertEquals(429, failure.getStatusCode().value());
    assertEquals("17", failure.getHeaders().getFirst("Retry-After"));
    server.verify();
  }
}
