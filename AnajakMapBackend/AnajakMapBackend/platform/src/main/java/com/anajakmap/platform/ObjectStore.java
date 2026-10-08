package com.anajakmap.platform;

import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class ObjectStore {
  private final String url, region, bucket, access, secret;
  private final HttpClient client =
      HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build();

  public ObjectStore(
      @Value("${anajak.object-url}") String u,
      @Value("${anajak.object-region}") String r,
      @Value("${anajak.object-bucket}") String b,
      @Value("${anajak.object-access-key}") String a,
      @Value("${anajak.object-secret-key}") String s) {
    url = u;
    region = r;
    bucket = b;
    access = a;
    secret = s;
  }

  public String upload(byte[] bytes, String mime) {
    MediaValidation.check(bytes, mime);
    String key = UUID.randomUUID().toString();
    request("PUT", key, bytes, mime);
    return key;
  }

  public void discardAfterFailure(String key, RuntimeException cause) {
    try {
      request("DELETE", key, new byte[0], "application/octet-stream");
    } catch (Exception cleanup) {
      cause.addSuppressed(cleanup);
      org.slf4j.LoggerFactory.getLogger(ObjectStore.class)
          .warn("object_cleanup_failed key={}", key);
    }
  }

  public byte[] download(String key) {
    if (!key.matches("[a-f0-9-]{36}")) throw new IllegalArgumentException();
    return request("GET", key, new byte[0], "application/octet-stream");
  }

  private byte[] request(String method, String key, byte[] bytes, String mime) {
    try {
      URI uri = URI.create(url + "/" + bucket + "/" + key);
      Instant now = Instant.now();
      String
          timestamp =
              DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'")
                  .withZone(ZoneOffset.UTC)
                  .format(now),
          day = timestamp.substring(0, 8);
      String contentHash =
          HexFormat.of()
              .formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(bytes));
      String headers =
          "host:"
              + uri.getRawAuthority()
              + "\nx-amz-content-sha256:"
              + contentHash
              + "\nx-amz-date:"
              + timestamp
              + "\n";
      String signed = "host;x-amz-content-sha256;x-amz-date";
      String canonical =
          method + "\n" + uri.getRawPath() + "\n\n" + headers + "\n" + signed + "\n" + contentHash;
      String scope = day + "/" + region + "/s3/aws4_request";
      String toSign =
          "AWS4-HMAC-SHA256\n" + timestamp + "\n" + scope + "\n" + Changes.hash(canonical);
      byte[] k = mac(("AWS4" + secret).getBytes(StandardCharsets.UTF_8), day);
      k = mac(k, region);
      k = mac(k, "s3");
      k = mac(k, "aws4_request");
      String auth =
          "AWS4-HMAC-SHA256 Credential="
              + access
              + "/"
              + scope
              + ", SignedHeaders="
              + signed
              + ", Signature="
              + HexFormat.of().formatHex(mac(k, toSign));
      var req =
          HttpRequest.newBuilder(uri)
              .timeout(Duration.ofSeconds(20))
              .header("x-amz-date", timestamp)
              .header("x-amz-content-sha256", contentHash)
              .header("Authorization", auth)
              .header("Content-Type", mime)
              .method(
                  method,
                  method.equals("GET")
                      ? HttpRequest.BodyPublishers.noBody()
                      : HttpRequest.BodyPublishers.ofByteArray(bytes))
              .build();
      var response = client.send(req, HttpResponse.BodyHandlers.ofByteArray());
      if (response.statusCode() < 200 || response.statusCode() >= 300)
        throw new IllegalStateException("Object storage status " + response.statusCode());
      return response.body();
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new IllegalStateException("Object storage interrupted", e);
    } catch (Exception e) {
      throw new IllegalStateException("Object storage failed", e);
    }
  }

  private byte[] mac(byte[] key, String data) throws Exception {
    Mac m = Mac.getInstance("HmacSHA256");
    m.init(new SecretKeySpec(key, "HmacSHA256"));
    return m.doFinal(data.getBytes(StandardCharsets.UTF_8));
  }
}
