package com.anajakmap.discovery.rpg;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import com.anajakmap.platform.*;
import com.nimbusds.jose.jwk.*;
import com.nimbusds.jose.jwk.source.ImmutableJWKSet;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(RpgApi.class)
@Import({Security.class,Success.class,Api.class})
class RpgApiTest {
  @Autowired MockMvc mvc;
  @MockitoBean RpgService service;
  @MockitoBean RateLimit limit;
  static final KeyPair keys=keys();
  static KeyPair keys(){try{var gen=KeyPairGenerator.getInstance("RSA");gen.initialize(2048);return gen.generateKeyPair();}catch(Exception e){throw new IllegalStateException(e);}}
  @DynamicPropertySource static void properties(DynamicPropertyRegistry registry){registry.add("anajak.jwt-public-key",()->Base64.getEncoder().encodeToString(keys.getPublic().getEncoded()));}
  String token() {
    var key=new RSAKey.Builder((java.security.interfaces.RSAPublicKey)keys.getPublic()).privateKey(keys.getPrivate()).build();
    var encoder=new NimbusJwtEncoder(new ImmutableJWKSet<>(new JWKSet(key)));
    return "Bearer "+encoder.encode(JwtEncoderParameters.from(JwsHeader.with(SignatureAlgorithm.RS256).build(),JwtClaimsSet.builder().issuer("anajakmap").audience(List.of("anajakmap-api")).subject("alice").issuedAt(Instant.now()).expiresAt(Instant.now().plusSeconds(120)).build())).getTokenValue();
  }
  @Test void unauthenticatedCannotReadOrMutate() throws Exception {
    mvc.perform(get("/api/v1/rpg/field/profile")).andExpect(status().isUnauthorized());
    mvc.perform(post("/api/v1/rpg/practice/encounters").contentType("application/json").content("{}")) .andExpect(status().isUnauthorized());
    verifyNoInteractions(service);
  }
  @Test void invalidActionsRejectedBeforeBusinessLogic() throws Exception {
    mvc.perform(post("/api/v1/rpg/practice/battles/test/actions").header("Authorization",token()).header("Idempotency-Key","test-key-123").contentType("application/json").content("{\"revision\":-1,\"move\":\"give-gold\"}")) .andExpect(status().isBadRequest());
    mvc.perform(post("/api/v1/rpg/practice/encounters").header("Authorization",token()).header("Idempotency-Key","test-key-123").contentType("application/json").content("{\"monsterId\":\"\",\"destinationId\":\"\"}")) .andExpect(status().isBadRequest());
    verifyNoInteractions(service);
  }
  @Test void signedActorAndEnvelopeReachFlutterContract() throws Exception {
    when(service.start(eq("alice"),eq("practice"),eq("test-key-123"),any())).thenReturn(Map.of("id","battle-1","revision",0,"status","active"));
    mvc.perform(post("/api/v1/rpg/practice/encounters").header("Authorization",token()).header("Idempotency-Key","test-key-123").contentType("application/json").content("{\"monsterId\":\"owned-1\",\"destinationId\":\"palace\",\"safeConfirmed\":true}"))
        .andExpect(status().isOk()).andExpect(jsonPath("$.data.id").value("battle-1")).andExpect(jsonPath("$.data.status").value("active"));
    verify(limit).check("rpg:alice",60,60);
  }
}
