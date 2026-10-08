package com.anajakmap.platform;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;

public final class MediaValidation {
  private MediaValidation() {}

  public static void check(byte[] bytes, String mime) {
    boolean valid =
        switch (mime) {
          case "image/png" ->
              bytes.length >= 8
                  && Arrays.equals(
                      Arrays.copyOf(bytes, 8), new byte[] {(byte) 137, 80, 78, 71, 13, 10, 26, 10});
          case "image/jpeg" ->
              bytes.length >= 3
                  && bytes[0] == (byte) 255
                  && bytes[1] == (byte) 216
                  && bytes[2] == (byte) 255;
          case "application/pdf" -> starts(bytes, "%PDF-");
          case "audio/wav" ->
              bytes.length >= 12
                  && starts(bytes, "RIFF")
                  && new String(bytes, 8, 4, StandardCharsets.US_ASCII).equals("WAVE");
          case "audio/mpeg" ->
              starts(bytes, "ID3")
                  || bytes.length >= 2 && bytes[0] == (byte) 255 && (bytes[1] & 224) == 224;
          default -> false;
        };
    if (!valid) throw new IllegalArgumentException("Media content does not match supported type");
  }

  private static boolean starts(byte[] bytes, String prefix) {
    return bytes.length >= prefix.length()
        && new String(bytes, 0, prefix.length(), StandardCharsets.US_ASCII).equals(prefix);
  }
}
