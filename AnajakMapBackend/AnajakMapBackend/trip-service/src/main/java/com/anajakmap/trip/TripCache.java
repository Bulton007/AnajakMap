package com.anajakmap.trip;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.util.Map;
import java.util.function.Supplier;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

@Component
public class TripCache {
  private final StringRedisTemplate redis;
  private final ObjectMapper json;

  public TripCache(StringRedisTemplate redis, ObjectMapper json) {
    this.redis = redis;
    this.json = json;
  }

  public Map<String, Object> calendar(
      String tripId, long version, Supplier<Map<String, Object>> load) {
    String key = "calendar:" + tripId + ":" + version;
    try {
      String value = redis.opsForValue().get(key);
      if (value != null) return json.readValue(value, Map.class);
      Map<String, Object> result = load.get();
      redis.opsForValue().set(key, json.writeValueAsString(result), Duration.ofSeconds(60));
      return result;
    } catch (org.springframework.data.redis.RedisConnectionFailureException unavailable) {
      return load.get();
    } catch (java.io.IOException invalid) {
      throw new IllegalStateException(invalid);
    }
  }

  public void invalidateAfterCommit(String tripId, long previousVersion) {
    if (!TransactionSynchronizationManager.isActualTransactionActive())
      throw new IllegalStateException("Cache eviction requires a transaction");
    TransactionSynchronizationManager.registerSynchronization(
        new TransactionSynchronization() {
          @Override
          public void afterCommit() {
            try {
              redis.delete("calendar:" + tripId + ":" + previousVersion);
            } catch (org.springframework.data.redis.RedisConnectionFailureException unavailable) {
              org.slf4j.LoggerFactory.getLogger(TripCache.class)
                  .warn("cache_eviction_deferred trip={}", tripId);
            }
          }
        });
  }
}
