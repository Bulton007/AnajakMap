package com.anajakmap.aiguide;

import com.anajakmap.platform.*;
import jakarta.validation.Validator;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;

@Component
public class JobWorker {
  private final JdbcTemplate jdbc;
  private final GuideProvider provider;
  private final Changes changes;
  private final Validator validator;
  private final TransactionTemplate tx;

  public JobWorker(
      JdbcTemplate j, GuideProvider p, Changes c, Validator v, PlatformTransactionManager t) {
    jdbc = j;
    provider = p;
    changes = c;
    validator = v;
    tx = new TransactionTemplate(t);
  }

  @Scheduled(fixedDelay = 1000)
  public void run() {
    jdbc.update(
        "UPDATE generation_jobs SET status='FAILED',error_code='WORKER_INTERRUPTED' WHERE"
            + " status='RUNNING' AND updated_at<CURRENT_TIMESTAMP-NUMTODSINTERVAL(120,'SECOND')");
    var rows =
        jdbc.queryForList(
            "SELECT id,owner_id,attempts,trace_id FROM generation_jobs WHERE status='QUEUED' AND"
                + " next_attempt<=CURRENT_TIMESTAMP ORDER BY created_at FETCH FIRST 5 ROWS ONLY");
    for (var r : rows) {
      String id = r.get("ID").toString();
      org.slf4j.MDC.put("traceId", java.util.Objects.toString(r.get("TRACE_ID"), id));
      if (jdbc.update(
              "UPDATE generation_jobs SET"
                  + " status='RUNNING',attempts=attempts+1,updated_at=CURRENT_TIMESTAMP WHERE id=? AND"
                  + " status='QUEUED'",
              id)
          != 1) continue;
      try {
        var in =
            new com.fasterxml.jackson.databind.ObjectMapper()
                .readValue(
                    jdbc.queryForObject(
                        "SELECT input_json FROM generation_jobs WHERE id=?", String.class, id),
                    Map.class);
        var result =
            provider.itinerary(
                (Map) in.get("trip"), (Map) in.get("preferences"), (List) in.get("places"));
        if (result == null || !validator.validate(result).isEmpty())
          throw new IllegalArgumentException("Invalid AI response");
        for (var stop : result.activities())
          if (!stop.endsAt().isAfter(stop.startsAt()))
            throw new IllegalArgumentException("Invalid AI timing");
        tx.executeWithoutResult(
            s -> {
              jdbc.update(
                  "UPDATE generation_jobs SET"
                      + " status='SUCCEEDED',output_json=?,updated_at=CURRENT_TIMESTAMP WHERE id=?",
                  changes.json(result),
                  id);
              changes.record(r.get("OWNER_ID").toString(), "ai.succeeded", id, Map.of());
            });
      } catch (Exception e) {
        int attempt = ((Number) r.get("ATTEMPTS")).intValue() + 1;
        var plan = failurePlan(e, attempt);
        jdbc.update(
            "UPDATE generation_jobs SET"
                + " status=?,error_code=?,next_attempt=CURRENT_TIMESTAMP+NUMTODSINTERVAL(?,'SECOND'),updated_at=CURRENT_TIMESTAMP"
                + " WHERE id=?",
            plan.retry() ? "QUEUED" : "FAILED",
            plan.code(),
            plan.delaySeconds(),
            id);
        org.slf4j.LoggerFactory.getLogger(JobWorker.class)
            .warn("ai_job_failed id={} type={}", id, e.getClass().getSimpleName());
      } finally {
        org.slf4j.MDC.clear();
      }
    }
  }

  record FailurePlan(boolean retry, String code, long delaySeconds) {}

  static FailurePlan failurePlan(Exception error, int attempt) {
    if (error instanceof IllegalArgumentException) return new FailurePlan(false, "INVALID_AI_RESPONSE", 0);
    if (error instanceof ResponseStatusException response && response.getStatusCode().value() == 429) {
      long delay = 0;
      try { delay = Long.parseLong(response.getHeaders().getFirst("Retry-After")); } catch (Exception ignored) { }
      return new FailurePlan(false, "AI_RATE_LIMITED", Math.max(0, Math.min(delay, 604800)));
    }
    return new FailurePlan(attempt < 3, "PROVIDER_FAILURE", 30L << Math.min(attempt - 1, 2));
  }
}
