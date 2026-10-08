package com.anajakmap.platform;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.*;
import javax.crypto.*;
import javax.crypto.spec.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class SecretVault {
  private final byte[] key;

  public SecretVault(@Value("${DATA_ENCRYPTION_KEY}") String k) {
    key = Base64.getDecoder().decode(k);
    if (key.length != 32)
      throw new IllegalArgumentException("DATA_ENCRYPTION_KEY must encode 32 bytes");
  }

  public String encrypt(String value) {
    try {
      byte[] nonce = new byte[12];
      new SecureRandom().nextBytes(nonce);
      Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
      c.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, nonce));
      byte[] encrypted = c.doFinal(value.getBytes(StandardCharsets.UTF_8));
      byte[] output = new byte[nonce.length + encrypted.length];
      System.arraycopy(nonce, 0, output, 0, nonce.length);
      System.arraycopy(encrypted, 0, output, nonce.length, encrypted.length);
      return Base64.getEncoder().encodeToString(output);
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }

  public String decrypt(String value) {
    try {
      byte[] input = Base64.getDecoder().decode(value);
      Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
      c.init(
          Cipher.DECRYPT_MODE,
          new SecretKeySpec(key, "AES"),
          new GCMParameterSpec(128, Arrays.copyOfRange(input, 0, 12)));
      return new String(
          c.doFinal(Arrays.copyOfRange(input, 12, input.length)), StandardCharsets.UTF_8);
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }
}
