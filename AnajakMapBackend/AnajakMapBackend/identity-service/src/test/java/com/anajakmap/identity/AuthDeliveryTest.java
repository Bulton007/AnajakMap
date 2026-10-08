package com.anajakmap.identity;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import com.anajakmap.platform.*;
import java.security.KeyPairGenerator;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.web.server.ResponseStatusException;

class AuthDeliveryTest {
  MockEnvironment environment() {
    return new MockEnvironment().withProperty("GMAIL_USERNAME", "sender@example.test")
        .withProperty("GMAIL_APP_PASSWORD", "test-only")
        .withProperty("AUTH_TERMS_URL", "https://example.test/terms")
        .withProperty("AUTH_PRIVACY_URL", "https://example.test/privacy")
        .withProperty("AUTH_POLICY_VERSION", "v1");
  }
  Auth auth(Accounts accounts, JdbcTemplate jdbc, AuthDelivery config) throws Exception {
    var generator = KeyPairGenerator.getInstance("RSA"); generator.initialize(2048);
    var pair = generator.generateKeyPair();
    return new Auth(mock(SecretVault.class), accounts, jdbc, mock(BCryptPasswordEncoder.class), mock(Changes.class), mock(RateLimit.class),
        Base64.getEncoder().encodeToString(pair.getPublic().getEncoded()),
        Base64.getEncoder().encodeToString(pair.getPrivate().getEncoded()), new MockEnvironment().withProperty("spring.profiles.active", "dev"), config);
  }
  @Test void missingSenderIsExplicitlyUnavailable() {
    var config = new AuthDelivery(new MockEnvironment());
    assertFalse(config.enabled()); assertFalse(config.legal());
    assertThrows(ResponseStatusException.class, config::requireDelivery);
    assertEquals(false, config.publicConfig().get("google"));
  }
  @Test void publicConfigurationNeverContainsCredentials() {
    var config = new AuthDelivery(environment());
    assertTrue(config.enabled()); assertTrue(config.legal());
    assertFalse(config.publicConfig().toString().contains("test-only"));
    assertThrows(IllegalArgumentException.class, () -> new AuthDelivery(environment().withProperty("AUTH_TERMS_URL", "http://example.test")));
  }
  @Test void registrationQueuesCodeButNeverReturnsItEvenInDev() throws Exception {
    var accounts = mock(Accounts.class); var jdbc = mock(JdbcTemplate.class);
    var auth = auth(accounts, jdbc, new AuthDelivery(environment()));
    var result = auth.register(new Auth.Registration("Traveler", "test@example.test", "ValidPassword!2026", true, "v1"));
    assertEquals("queued", result.get("delivery"));
    assertEquals(60, result.get("retryAfterSeconds"));
    assertFalse(result.containsKey("developmentCode")); assertFalse(result.containsKey("code"));
    var captured = org.mockito.ArgumentCaptor.forClass(Account.class);
    verify(accounts).saveAndFlush(captured.capture());
    assertEquals("Traveler", captured.getValue().displayName);
    assertEquals("v1", captured.getValue().legalVersion);
    assertNotNull(captured.getValue().legalAcceptedAt);
    assertThrows(ResponseStatusException.class, () -> auth.register(new Auth.Registration("Traveler", "test@example.test", "ValidPassword!2026", false, "v1")));
  }
  @Test void recoveryAndResendResponsesDoNotRevealAccountExistence() throws Exception {
    var accounts = mock(Accounts.class); var jdbc = mock(JdbcTemplate.class);
    var auth = auth(accounts, jdbc, new AuthDelivery(environment()));
    var request = new Auth.EmailRequest("test@example.test");
    when(accounts.findByEmail(anyString())).thenReturn(Optional.empty());
    var unknown = auth.forgot(request); var unknownResend = auth.resend(request);
    var account = new Account(); account.id = "id"; account.email = request.email();
    when(accounts.findByEmail(anyString())).thenReturn(Optional.of(account));
    assertEquals(unknown, auth.forgot(request)); assertEquals(unknownResend, auth.resend(request));
  }
  @Test void invalidCodeCannotVerifyOrReset() throws Exception {
    var accounts = mock(Accounts.class); var jdbc = mock(JdbcTemplate.class);
    var auth = auth(accounts, jdbc, new AuthDelivery(environment()));
    var account = new Account(); account.id = "id"; account.email = "test@example.test";
    when(accounts.findByEmail(anyString())).thenReturn(Optional.of(account));
    assertThrows(ResponseStatusException.class, () -> auth.verify(new Auth.Verify(account.email, "123456")));
    assertThrows(ResponseStatusException.class, () -> auth.reset(new Auth.Reset(account.email, "123456", "ValidPassword!2026")));
    assertFalse(account.verified);
  }
  @Test void emailContainsExpiryAndEncodedFragmentLink() {
    String message = MailWorker.message("RESET", "123456", "a+b@example.test", "https://example.test/auth/link");
    assertTrue(message.contains("15 minutes"));
    assertTrue(message.contains("#reset?email=a%2Bb%40example.test&code=123456"));
    assertFalse(MailWorker.message("VERIFY", "123456", "a@example.test", "").contains("https://"));
  }
}
