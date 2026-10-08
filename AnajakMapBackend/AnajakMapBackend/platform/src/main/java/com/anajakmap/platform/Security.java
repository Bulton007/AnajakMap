package com.anajakmap.platform;

import java.security.*;
import java.security.interfaces.*;
import java.security.spec.*;
import java.util.Base64;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.oauth2.core.*;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
public class Security {
  public static RSAPublicKey publicKey(String pem) {
    try {
      return (RSAPublicKey)
          KeyFactory.getInstance("RSA").generatePublic(new X509EncodedKeySpec(decode(pem)));
    } catch (Exception e) {
      throw new IllegalArgumentException("Invalid JWT public key", e);
    }
  }

  public static RSAPrivateKey privateKey(String pem) {
    try {
      return (RSAPrivateKey)
          KeyFactory.getInstance("RSA").generatePrivate(new PKCS8EncodedKeySpec(decode(pem)));
    } catch (Exception e) {
      throw new IllegalArgumentException("Invalid JWT private key", e);
    }
  }

  private static byte[] decode(String pem) {
    return Base64.getDecoder().decode(pem.replaceAll("-----[^-]+-----", "").replaceAll("\\s", ""));
  }

  @Bean
  JwtDecoder decoder(@Value("${anajak.jwt-public-key}") String pem) {
    var d = NimbusJwtDecoder.withPublicKey(publicKey(pem)).build();
    d.setJwtValidator(
        new DelegatingOAuth2TokenValidator<>(
            JwtValidators.createDefaultWithIssuer("anajakmap"),
            jwt ->
                jwt.getAudience().contains("anajakmap-api")
                    ? OAuth2TokenValidatorResult.success()
                    : OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token"))));
    return d;
  }

  @Bean
  BCryptPasswordEncoder passwordEncoder() {
    return new BCryptPasswordEncoder(12);
  }

  @Bean
  SecurityFilterChain chain(HttpSecurity http) throws Exception {
    return http.cors(org.springframework.security.config.Customizer.withDefaults()).csrf(c -> c.disable())
        .sessionManagement(c -> c.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
        .authorizeHttpRequests(
            c ->
                c.requestMatchers(
                        "/api/v1/auth/**",
                        "/actuator/health/**",
                        "/v3/api-docs/**",
                        "/swagger-ui/**",
                        "/swagger-ui.html")
                    .permitAll()
                    .anyRequest()
                    .authenticated())
        .exceptionHandling(
            c ->
                c.authenticationEntryPoint((req, res, e) -> error(res, 401, "UNAUTHORIZED"))
                    .accessDeniedHandler((req, res, e) -> error(res, 403, "FORBIDDEN")))
        .oauth2ResourceServer(
            c ->
                c.jwt(j -> {})
                    .authenticationEntryPoint((req, res, e) -> error(res, 401, "UNAUTHORIZED")))
        .build();
  }

  @Bean
  org.springframework.web.cors.CorsConfigurationSource corsConfigurationSource(
      @Value("${CORS_ALLOWED_ORIGINS:}") String origins) {
    var config = new org.springframework.web.cors.CorsConfiguration();
    config.setAllowedOrigins(java.util.Arrays.stream(origins.split(","))
        .map(String::trim).filter(s -> !s.isEmpty()).toList());
    config.setAllowedMethods(java.util.List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
    config.setAllowedHeaders(java.util.List.of("Authorization", "Content-Type", "Idempotency-Key", "If-Match", "X-Trace-ID"));
    config.setExposedHeaders(java.util.List.of("X-Trace-ID", "Retry-After"));
    config.setAllowCredentials(false);
    config.setMaxAge(3600L);
    var source = new org.springframework.web.cors.UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/api/v1/**", config);
    return source;
  }

  private static void error(jakarta.servlet.http.HttpServletResponse res, int status, String code)
      throws java.io.IOException {
    res.setStatus(status);
    res.setContentType("application/json");
    res.getWriter()
        .write(
            new com.fasterxml.jackson.databind.ObjectMapper()
                .findAndRegisterModules()
                .writeValueAsString(
                    new Api.Error(
                        code,
                        "Authentication or permission required",
                        org.slf4j.MDC.get("traceId"),
                        java.time.Instant.now())));
  }
}
