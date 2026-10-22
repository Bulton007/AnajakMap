package com.anajakmap.aiguide;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;
import org.springframework.http.*;
import org.springframework.web.server.ResponseStatusException;

class JobWorkerRetryTest {
  @Test void exhaustedQuotaDoesNotTriggerRapidAutomaticRetries() {
    var error = new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS) {
      @Override public HttpHeaders getHeaders() {
        var headers = new HttpHeaders(); headers.set("Retry-After", "53959"); return headers;
      }
    };
    var plan = JobWorker.failurePlan(error, 1);
    assertFalse(plan.retry());
    assertEquals("AI_RATE_LIMITED", plan.code());
    assertEquals(53959, plan.delaySeconds());
  }
  @Test void providerOutageUsesBoundedSlowerBackoff() {
    var error = new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
    assertTrue(JobWorker.failurePlan(error, 1).retry());
    assertEquals(30, JobWorker.failurePlan(error, 1).delaySeconds());
    assertEquals(60, JobWorker.failurePlan(error, 2).delaySeconds());
    assertFalse(JobWorker.failurePlan(error, 3).retry());
    assertFalse(JobWorker.failurePlan(new IllegalArgumentException(), 1).retry());
  }
  @Test void retryMetadataIsParsedWithoutReturningProviderBody() {
    var body = "{\"error\":{\"details\":[{\"retryDelay\":\"53959.2s\"}]}}".getBytes(java.nio.charset.StandardCharsets.UTF_8);
    assertEquals(53960, GeminiGuideProvider.retryDelay("60", body));
    assertEquals(0, GeminiGuideProvider.retryDelay(null, new byte[0]));
  }
}
