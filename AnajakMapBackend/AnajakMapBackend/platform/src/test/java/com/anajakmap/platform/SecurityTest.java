package com.anajakmap.platform;

import static org.junit.jupiter.api.Assertions.*;

import com.nimbusds.jose.jwk.*;
import com.nimbusds.jose.jwk.source.ImmutableJWKSet;
import java.security.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.jwt.*;

class SecurityTest {
  @Test
  void validatesIssuerAudienceExpiryAndSignature() throws Exception {
    var k = KeyPairGenerator.getInstance("RSA");
    k.initialize(2048);
    var pair = k.generateKeyPair();
    var key =
        new RSAKey.Builder((java.security.interfaces.RSAPublicKey) pair.getPublic())
            .privateKey(pair.getPrivate())
            .build();
    var encoder = new NimbusJwtEncoder(new ImmutableJWKSet<>(new JWKSet(key)));
    var decoder =
        new Security().decoder(Base64.getEncoder().encodeToString(pair.getPublic().getEncoded()));
    assertEquals(
        "user",
        decoder
            .decode(token(encoder, "anajakmap", "anajakmap-api", Instant.now().plusSeconds(60)))
            .getSubject());
    assertThrows(
        JwtException.class,
        () ->
            decoder.decode(token(encoder, "evil", "anajakmap-api", Instant.now().plusSeconds(60))));
    assertThrows(
        JwtException.class,
        () -> decoder.decode(token(encoder, "anajakmap", "other", Instant.now().plusSeconds(60))));
    assertThrows(
        JwtException.class,
        () ->
            decoder.decode(
                token(encoder, "anajakmap", "anajakmap-api", Instant.now().minusSeconds(120))));
    var other = k.generateKeyPair();
    assertThrows(
        JwtException.class,
        () ->
            new Security()
                .decoder(Base64.getEncoder().encodeToString(other.getPublic().getEncoded()))
                .decode(
                    token(encoder, "anajakmap", "anajakmap-api", Instant.now().plusSeconds(60))));
  }

  private String token(JwtEncoder e, String issuer, String audience, Instant expiry) {
    return e.encode(
            JwtEncoderParameters.from(
                JwsHeader.with(SignatureAlgorithm.RS256).build(),
                JwtClaimsSet.builder()
                    .issuer(issuer)
                    .audience(List.of(audience))
                    .subject("user")
                    .issuedAt(Instant.now().minusSeconds(300))
                    .expiresAt(expiry)
                    .build()))
        .getTokenValue();
  }

  @Test
  void hashesDeterministically() {
    assertEquals(64, Changes.hash("test").length());
    assertNotEquals(Changes.hash("a"), Changes.hash("b"));
  }
}
