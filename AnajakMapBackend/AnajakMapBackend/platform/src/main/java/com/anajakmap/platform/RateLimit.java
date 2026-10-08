package com.anajakmap.platform;

import java.util.List;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

@Component
public class RateLimit {
  private final StringRedisTemplate redis;

  public RateLimit(StringRedisTemplate r) {
    redis = r;
  }

  public void check(String key, int limit, int seconds) {
    Long n =
        redis.execute(
            new DefaultRedisScript<Long>(
                "local n=redis.call('INCR',KEYS[1]); if n==1 then"
                    + " redis.call('EXPIRE',KEYS[1],ARGV[1]) end; return n",
                Long.class),
            List.of("rl:" + key),
            Integer.toString(seconds));
    if (n == null || n > limit) {
      Long remaining = redis.getExpire("rl:" + key);
      long retryAfter = remaining == null || remaining < 1 ? seconds : remaining;
      throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "Rate limit exceeded") {
        @Override public org.springframework.http.HttpHeaders getHeaders() {
          var headers = new org.springframework.http.HttpHeaders();
          headers.set("Retry-After", Long.toString(retryAfter));
          return headers;
        }
      };
    }
  }
}
