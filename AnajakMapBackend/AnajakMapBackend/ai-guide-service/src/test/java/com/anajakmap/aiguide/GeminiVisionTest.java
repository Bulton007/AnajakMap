package com.anajakmap.aiguide;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;
import java.util.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

class GeminiVisionTest {
  RestClient.Builder builder = RestClient.builder().baseUrl("https://generativelanguage.googleapis.com");
  MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
  GeminiGuideProvider enabled = new GeminiGuideProvider("test-key", "gemini-test", builder.build(), true);
  Map<String,Object> input() {
    return new HashMap<>(Map.of("shareWithProvider", true, "mimeType", "image/png", "language", "km",
        "imageBase64", Base64.getEncoder().encodeToString(new byte[]{(byte)137,80,78,71,13,10,26,10})));
  }
  @Test void disabledAndUnconsentedNeverCallGoogle() {
    var disabled = new GeminiGuideProvider("test-key", "gemini-test", builder.build());
    assertEquals(false, disabled.capabilities().get("vision"));
    assertThrows(ResponseStatusException.class, () -> disabled.perform("vision", input()));
    var data = input(); data.remove("shareWithProvider");
    assertThrows(IllegalArgumentException.class, () -> enabled.perform("vision", data));
    server.verify();
  }
  @Test void rejectsWrongTypeCorruptAndOversizedMediaBeforeProvider() {
    var data = input(); data.put("mimeType", "application/pdf");
    assertThrows(IllegalArgumentException.class, () -> enabled.perform("vision", data));
    data.put("mimeType", "image/png"); data.put("imageBase64", "AAAA");
    assertThrows(IllegalArgumentException.class, () -> enabled.perform("vision", data));
    data.put("imageBase64", "A".repeat(5600001));
    assertThrows(IllegalArgumentException.class, () -> enabled.perform("vision", data));
    server.verify();
  }
  @Test void sendsInlineImageOnlyAfterConsentAndLabelsUncertainty() throws Exception {
    String answer = "{\"possibleLandmarks\":[{\"name\":\"Possible temple\",\"confidence\":0.4}],\"explanation\":\"Uncertain\",\"extractedText\":\"\"}";
    server.expect(anything()).andExpect(content().string(org.hamcrest.Matchers.containsString("inlineData")))
        .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("private-owner"))))
        .andRespond(withSuccess(new ObjectMapper().writeValueAsString(Map.of("candidates", List.of(Map.of(
            "finishReason", "STOP", "content", Map.of("parts", List.of(Map.of("text", answer))))))), MediaType.APPLICATION_JSON));
    var data = input(); data.put("ownerId", "private-owner");
    var result = enabled.perform("vision", data);
    assertEquals(true, result.get("requiresVerification"));
    assertEquals(false, result.get("mock"));
    server.verify();
  }
}
