package com.anajakmap.identity;

import java.net.URI;
import java.util.Map;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

/** Server-only delivery and legal configuration. Never returned credentials. */
@Component
public class AuthDelivery {
  final String username, password, providerUrl, providerKey, linkBase;
  final String termsUrl, privacyUrl, policyVersion;
  public AuthDelivery(Environment env) {
    username = env.getProperty("GMAIL_USERNAME", "");
    password = env.getProperty("GMAIL_APP_PASSWORD", "");
    providerUrl = env.getProperty("MAIL_PROVIDER_URL", "");
    providerKey = env.getProperty("MAIL_PROVIDER_KEY", "");
    linkBase = env.getProperty("AUTH_LINK_BASE", "");
    termsUrl = env.getProperty("AUTH_TERMS_URL", "");
    privacyUrl = env.getProperty("AUTH_PRIVACY_URL", "");
    policyVersion = env.getProperty("AUTH_POLICY_VERSION", "");
    for (String url : new String[]{linkBase, termsUrl, privacyUrl}) {
      if (!url.isBlank() && !https(url)) throw new IllegalArgumentException("Auth public URLs must be HTTPS without credentials/query/fragment");
    }
  }
  private boolean https(String value) {
    try {
      URI uri = URI.create(value);
      return "https".equals(uri.getScheme()) && uri.getHost() != null
          && uri.getUserInfo() == null && uri.getQuery() == null && uri.getFragment() == null;
    } catch (IllegalArgumentException e) { return false; }
  }
  boolean gmail() { return !username.isBlank() && !password.isBlank(); }
  boolean enabled() { return gmail() || (!providerUrl.isBlank() && !providerKey.isBlank()); }
  boolean legal() { return !termsUrl.isBlank() && !privacyUrl.isBlank() && !policyVersion.isBlank(); }
  void requireDelivery() {
    if (!enabled()) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Email delivery is not configured");
  }
  Map<String, Object> publicConfig() {
    return Map.of("emailDelivery", enabled(), "registration", enabled() && legal(),
        "termsUrl", termsUrl, "privacyUrl", privacyUrl, "policyVersion", policyVersion,
        "google", false, "apple", false, "passwordMinLength", 12, "passwordMaxBytes", 72);
  }
}
