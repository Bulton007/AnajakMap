package com.anajakmap.platform;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class MediaValidationTest {
  @Test
  void rejectsSpoofedImageMimeAndAcceptsPngSignature() {
    assertThrows(
        IllegalArgumentException.class,
        () -> MediaValidation.check("not-an-image".getBytes(), "image/png"));
    assertDoesNotThrow(
        () ->
            MediaValidation.check(
                new byte[] {(byte) 137, 80, 78, 71, 13, 10, 26, 10}, "image/png"));
  }
}
