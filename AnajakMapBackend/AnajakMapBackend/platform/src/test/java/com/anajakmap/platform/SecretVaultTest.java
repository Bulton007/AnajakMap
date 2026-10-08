package com.anajakmap.platform;

import static org.junit.jupiter.api.Assertions.*;

import java.util.Base64;
import org.junit.jupiter.api.Test;

class SecretVaultTest {
  @Test
  void ciphertextIsAuthenticatedAndRandomized() {
    var vault = new SecretVault(Base64.getEncoder().encodeToString(new byte[32]));
    String a = vault.encrypt("private-token"), b = vault.encrypt("private-token");
    assertNotEquals(a, b);
    assertEquals("private-token", vault.decrypt(a));
    byte[] bytes = Base64.getDecoder().decode(a);
    bytes[20] ^= 1;
    assertThrows(
        IllegalStateException.class,
        () -> vault.decrypt(Base64.getEncoder().encodeToString(bytes)));
  }
}
