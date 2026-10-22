package com.anajakmap.identity;

import com.anajakmap.platform.*;
import com.nimbusds.jose.jwk.*;
import com.nimbusds.jose.jwk.source.ImmutableJWKSet;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.security.SecureRandom;
import java.time.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1")
public class Auth {
  private final SecretVault vault;
  private final Accounts accounts;
  private final JdbcTemplate jdbc;
  private final BCryptPasswordEncoder passwords;
  private final Changes changes;
  private final RateLimit limit;
  private final JwtEncoder encoder;
  private final AuthDelivery delivery;

  public Auth(
      SecretVault vault,
      Accounts a,
      JdbcTemplate j,
      BCryptPasswordEncoder p,
      Changes c,
      RateLimit l,
      @Value("${anajak.jwt-public-key}") String pub,
      @Value("${anajak.jwt-private-key}") String priv,
      Environment env,
      AuthDelivery delivery) {
    this.vault = vault;
    accounts = a;
    jdbc = j;
    passwords = p;
    changes = c;
    limit = l;
    this.delivery = delivery;
    var key =
        new RSAKey.Builder(Security.publicKey(pub))
            .privateKey(Security.privateKey(priv))
            .keyID("anajak-1")
            .build();
    encoder = new NimbusJwtEncoder(new ImmutableJWKSet<>(new JWKSet(key)));
  }

  public record Credentials(
      @Email @NotBlank String email, @NotBlank @Size(min = 12, max = 72) String password) {}

  public record Registration(
      @NotBlank @Size(max = 120) String name,
      @Email @NotBlank String email,
      @NotBlank @Size(min = 12, max = 72) String password,
      @AssertTrue boolean legalConsent,
      @NotBlank @Size(max = 120) String policyVersion) {}

  @GetMapping("/auth/config")
  public Map<String, Object> config() { return delivery.publicConfig(); }

  public record Verify(@Email @NotBlank String email, @NotBlank String code) {}

  public record Reset(
      @Email @NotBlank String email,
      @NotBlank String code,
      @NotBlank @Size(min = 12, max = 72) String password) {}

  public record EmailRequest(@Email @NotBlank String email) {}

  public record Refresh(@NotBlank String refreshToken) {}

  public record Prefs(@NotNull Map<String, Object> preferences, long version) {}

  private String email(String e) {
    return e.trim().toLowerCase(Locale.ROOT);
  }

  private String random() {
    byte[] b = new byte[32];
    new SecureRandom().nextBytes(b);
    return Base64.getUrlEncoder().withoutPadding().encodeToString(b);
  }

  private Account account(String e) {
    return accounts
        .findByEmail(email(e))
        .orElseThrow(
            () -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid credentials"));
  }

  @PostMapping("/auth/register")
  @ResponseStatus(HttpStatus.CREATED)
  @Transactional
  public Map<String, Object> register(@Valid @RequestBody Registration r) {
    delivery.requireDelivery();
    if (!delivery.legal()) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Legal documents are not configured");
    if (!r.legalConsent || !delivery.policyVersion.equals(r.policyVersion))
      throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Current legal consent is required");
    validatePassword(r.password);
    limit.check("register:" + Changes.hash(email(r.email)), 5, 3600);
    limit.check("send:VERIFY:" + Changes.hash(email(r.email)), 1, 60);
    Account a = new Account();
    a.id = UUID.randomUUID().toString();
    a.email = email(r.email);
    a.displayName = r.name.trim();
    a.legalVersion = r.policyVersion;
    a.legalAcceptedAt = Instant.now();
    a.passwordHash = passwords.encode(r.password);
    accounts.saveAndFlush(a);
    changes.record(a.id, "account.registered", a.id, Map.of());
    return issueCode(a, "VERIFY");
  }

  private Map<String, Object> issueCode(Account a, String kind) {
    String code = String.format(Locale.ROOT, "%06d", new SecureRandom().nextInt(1000000));
    jdbc.update("DELETE FROM auth_codes WHERE account_id=? AND kind=?", a.id, kind);
    jdbc.update(
        "INSERT INTO auth_codes(id,account_id,kind,code_hash,expires_at) VALUES(?,?,?,?,?)",
        UUID.randomUUID().toString(),
        a.id,
        kind,
        Changes.hash(code),
        java.sql.Timestamp.from(Instant.now().plusSeconds(900)));
    jdbc.update("DELETE FROM mail_delivery WHERE recipient=? AND kind=? AND sent=0", a.email, kind);
    jdbc.update(
          "INSERT INTO mail_delivery(id,recipient,kind,secret_value,expires_at) VALUES(?,?,?,?,?)",
          UUID.randomUUID().toString(),
          a.email,
          kind,
          vault.encrypt(code),
          java.sql.Timestamp.from(Instant.now().plusSeconds(900)));
    return Map.of("delivery", "queued", "retryAfterSeconds", 60, "expiresIn", 900);
  }

  private void consumeCode(Account a, String code, String kind) {
    var rows =
        jdbc.queryForList(
            "SELECT id FROM auth_codes WHERE account_id=? AND kind=? AND code_hash=? AND"
                + " expires_at>CURRENT_TIMESTAMP FOR UPDATE",
            a.id,
            kind,
            Changes.hash(code));
    if (rows.isEmpty())
      throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid or expired code");
    jdbc.update("DELETE FROM auth_codes WHERE id=?", rows.getFirst().get("ID"));
  }

  @PostMapping("/auth/verify")
  @Transactional
  public Map<String, Object> verify(@Valid @RequestBody Verify r) {
    limit.check("verify:" + Changes.hash(email(r.email)), 5, 900);
    Account a = accounts.findByEmail(email(r.email)).orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid or expired code"));
    consumeCode(a, r.code, "VERIFY");
    a.verified = true;
    changes.record(a.id, "account.verified", a.id, Map.of());
    return Map.of("verified", true);
  }

  @PostMapping("/auth/login")
  @Transactional
  public Map<String, Object> login(@Valid @RequestBody Credentials r) {
    validatePassword(r.password);
    limit.check("login:" + Changes.hash(email(r.email)), 10, 900);
    Account a = account(r.email);
    if (!passwords.matches(r.password, a.passwordHash))
      throw new ResponseStatusException(
          HttpStatus.UNAUTHORIZED, "Invalid credentials");
    if (!a.verified) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "EMAIL_UNVERIFIED");
    return tokens(a);
  }

  private Map<String, Object> tokens(Account a) {
    Instant now = Instant.now();
    var claims =
        JwtClaimsSet.builder()
            .issuer("anajakmap")
            .subject(a.id)
            .audience(List.of("anajakmap-api"))
            .issuedAt(now)
            .expiresAt(now.plusSeconds(600))
            .id(UUID.randomUUID().toString())
            .build();
    String access =
        encoder
            .encode(
                JwtEncoderParameters.from(
                    JwsHeader.with(
                            org.springframework.security.oauth2.jose.jws.SignatureAlgorithm.RS256)
                        .keyId("anajak-1")
                        .build(),
                    claims))
            .getTokenValue();
    String refresh = random();
    jdbc.update(
        "INSERT INTO refresh_tokens(token_hash,account_id,expires_at) VALUES(?,?,?)",
        Changes.hash(refresh),
        a.id,
        java.sql.Timestamp.from(now.plus(Duration.ofDays(30))));
    return Map.of(
        "accessToken", access, "refreshToken", refresh, "expiresIn", 600, "tokenType", "Bearer");
  }

  @PostMapping("/auth/refresh")
  @Transactional
  public Map<String, Object> refresh(@Valid @RequestBody Refresh r) {
    limit.check("refresh:" + Changes.hash(r.refreshToken), 10, 900);
    var rows =
        jdbc.queryForList(
            "SELECT account_id FROM refresh_tokens WHERE token_hash=? AND revoked=0 AND"
                + " expires_at>CURRENT_TIMESTAMP FOR UPDATE",
            Changes.hash(r.refreshToken));
    if (rows.isEmpty())
      throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid refresh token");
    jdbc.update(
        "UPDATE refresh_tokens SET revoked=1 WHERE token_hash=?", Changes.hash(r.refreshToken));
    return tokens(
        accounts.findById(rows.getFirst().get("ACCOUNT_ID").toString()).orElseThrow(Api::missing));
  }

  @PostMapping("/auth/logout")
  @Transactional
  public Map<String, Boolean> logout(@Valid @RequestBody Refresh r) {
    jdbc.update(
        "UPDATE refresh_tokens SET revoked=1 WHERE token_hash=?", Changes.hash(r.refreshToken));
    return Map.of("loggedOut", true);
  }

  @PostMapping("/auth/forgot-password")
  @Transactional
  public Map<String, Object> forgot(@Valid @RequestBody EmailRequest r) {
    delivery.requireDelivery();
    limit.check("forgot:" + Changes.hash(email(r.email)), 3, 3600);
    limit.check("send:RESET:" + Changes.hash(email(r.email)), 1, 60);
    var a = accounts.findByEmail(email(r.email));
    if (a.isPresent()) {
      issueCode(a.get(), "RESET");
    }
    return Map.of("delivery", "If the account exists, instructions are queued", "retryAfterSeconds", 60, "expiresIn", 900);
  }

  @PostMapping("/auth/resend-verification")
  @Transactional
  public Map<String, Object> resend(@Valid @RequestBody EmailRequest r) {
    delivery.requireDelivery();
    limit.check("resend:" + Changes.hash(email(r.email)), 3, 3600);
    // Apply identical cooldown even for an unknown/verified email.
    limit.check("send:VERIFY:" + Changes.hash(email(r.email)), 1, 60);
    var account = accounts.findByEmail(email(r.email));
    if (account.isPresent() && !account.get().verified) issueCode(account.get(), "VERIFY");
    return Map.of("delivery", "If verification is needed, instructions are queued", "retryAfterSeconds", 60, "expiresIn", 900);
  }

  @PostMapping("/auth/reset-password")
  @Transactional
  public Map<String, Boolean> reset(@Valid @RequestBody Reset r) {
    validatePassword(r.password);
    limit.check("reset:" + Changes.hash(email(r.email)), 5, 900);
    var a = accounts.findByEmail(email(r.email)).orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid or expired code"));
    consumeCode(a, r.code, "RESET");
    a.passwordHash = passwords.encode(r.password);
    jdbc.update("UPDATE refresh_tokens SET revoked=1 WHERE account_id=?", a.id);
    changes.record(a.id, "account.password-reset", a.id, Map.of());
    return Map.of("reset", true);
  }

  @GetMapping("/profile")
  public Map<String, Object> profile(@AuthenticationPrincipal Jwt jwt) {
    var a = accounts.findById(jwt.getSubject()).orElseThrow(Api::missing);
    return Map.of(
        "id", a.id, "email", a.email, "name", a.displayName == null ? "" : a.displayName,
        "verified", a.verified, "preferences", read(a.preferences), "version", a.version);
  }

  private Object read(String s) {
    try {
      return new com.fasterxml.jackson.databind.ObjectMapper().readValue(s, Map.class);
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }

  @PutMapping("/profile/preferences")
  @Transactional
  public Map<String, Object> preferences(
      @AuthenticationPrincipal Jwt jwt, @Valid @RequestBody Prefs r) {
    var a = accounts.findById(jwt.getSubject()).orElseThrow(Api::missing);
    if (a.version != r.version) throw Api.conflict();
    if (changes.json(r.preferences).length() > 8000) throw new IllegalArgumentException();
    a.preferences = changes.json(r.preferences);
    accounts.flush();
    changes.record(a.id, "preferences.updated", a.id, Map.of("version", a.version));
    return Map.of("preferences", r.preferences, "version", a.version);
  }

  private static void validatePassword(String password) {
    if (password.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 72)
      throw new IllegalArgumentException("Password exceeds supported byte length");
  }
}
