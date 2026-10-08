package com.anajakmap.trip;

import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.transaction.support.TransactionSynchronizationManager;

class TripCacheTest {
  @Test
  void evictionWaitsForCommitAndDoesNotRunOnRollback() {
    var redis = mock(StringRedisTemplate.class);
    var cache = new TripCache(redis, new ObjectMapper());
    TransactionSynchronizationManager.initSynchronization();
    TransactionSynchronizationManager.setActualTransactionActive(true);
    try {
      cache.invalidateAfterCommit("trip", 4);
      verifyNoInteractions(redis);
      var callback = TransactionSynchronizationManager.getSynchronizations().getFirst();
      callback.afterCompletion(
          org.springframework.transaction.support.TransactionSynchronization.STATUS_ROLLED_BACK);
      verifyNoInteractions(redis);
      callback.afterCommit();
      verify(redis).delete("calendar:trip:4");
    } finally {
      TransactionSynchronizationManager.clearSynchronization();
      TransactionSynchronizationManager.setActualTransactionActive(false);
    }
  }
}
