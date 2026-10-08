package com.anajakmap.aiguide;

import com.anajakmap.platform.*;
import jakarta.validation.Validator;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

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
            + " status='RUNNING' AND updated_at<SYSTIMESTAMP-NUMTODSINTERVAL(120,'SECOND')");
    var rows =
        jdbc.queryForList(
            "SELECT id,owner_id,attempts,trace_id FROM generation_jobs WHERE status='QUEUED' AND"
                + " next_attempt<=SYSTIMESTAMP ORDER BY created_at FETCH FIRST 5 ROWS ONLY");
    for (var r : rows) {
      String id = r.get("ID").toString();
      org.slf4j.MDC.put("traceId", java.util.Objects.toString(r.get("TRACE_ID"), id));
      if (jdbc.update(
              "UPDATE generation_jobs SET"
                  + " status='RUNNING',attempts=attempts+1,updated_at=SYSTIMESTAMP WHERE id=? AND"
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
                      + " status='SUCCEEDED',output_json=?,updated_at=SYSTIMESTAMP WHERE id=?",
                  changes.json(result),
                  id);
              changes.record(r.get("OWNER_ID").toString(), "ai.succeeded", id, Map.of());
            });
      } catch (Exception e) {
        boolean invalid = e instanceof IllegalArgumentException;
        int attempt = ((Number) r.get("ATTEMPTS")).intValue() + 1;
        jdbc.update(
            "UPDATE generation_jobs SET"
                + " status=?,error_code=?,next_attempt=SYSTIMESTAMP+NUMTODSINTERVAL(?,'SECOND'),updated_at=SYSTIMESTAMP"
                + " WHERE id=?",
            invalid || attempt >= 3 ? "FAILED" : "QUEUED",
            invalid ? "INVALID_AI_RESPONSE" : "PROVIDER_FAILURE",
            1 << attempt,
            id);
        org.slf4j.LoggerFactory.getLogger(JobWorker.class)
            .warn("ai_job_failed id={} type={}", id, e.getClass().getSimpleName());
      } finally {
        org.slf4j.MDC.clear();
      }
    }
  }
}
