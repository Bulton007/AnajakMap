package com.anajakmap.aiguide;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

/** Validates a bounded recording before storage or any external provider request. */
final class VoiceAudio {
  static final int MAX_BYTES = 4 * 1024 * 1024;
  private VoiceAudio() {}

  static void validate(byte[] bytes, String mime) {
    if (!"audio/wav".equals(mime) || bytes.length < 44 || bytes.length > MAX_BYTES
        || !tag(bytes, 0, "RIFF") || !tag(bytes, 8, "WAVE")) throw invalid();
    var buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
    if (Integer.toUnsignedLong(buffer.getInt(4)) != bytes.length - 8L) throw invalid();
    long byteRate = 0, dataBytes = 0;
    int blockAlign = 0;
    boolean formatFound = false, dataFound = false;
    int offset = 12;
    while (offset + 8 <= bytes.length) {
      long length = Integer.toUnsignedLong(buffer.getInt(offset + 4));
      long next = offset + 8L + length + (length % 2);
      if (next > bytes.length) throw invalid();
      if (tag(bytes, offset, "fmt ")) {
        if (formatFound || length < 16) throw invalid();
        int format = Short.toUnsignedInt(buffer.getShort(offset + 8));
        int channels = Short.toUnsignedInt(buffer.getShort(offset + 10));
        long sampleRate = Integer.toUnsignedLong(buffer.getInt(offset + 12));
        byteRate = Integer.toUnsignedLong(buffer.getInt(offset + 16));
        blockAlign = Short.toUnsignedInt(buffer.getShort(offset + 20));
        int bits = Short.toUnsignedInt(buffer.getShort(offset + 22));
        if (format != 1 || (channels != 1 && channels != 2) || bits != 16
            || sampleRate < 8000 || sampleRate > 48000 || blockAlign != channels * 2
            || byteRate != sampleRate * blockAlign) throw invalid();
        formatFound = true;
      } else if (tag(bytes, offset, "data")) {
        if (dataFound || length == 0) throw invalid();
        dataBytes = length;
        dataFound = true;
      }
      offset = (int) next;
    }
    if (offset != bytes.length || !formatFound || !dataFound || dataBytes % blockAlign != 0
        || dataBytes > byteRate * 60 || dataBytes < byteRate / 4) throw invalid();
  }

  private static boolean tag(byte[] bytes, int offset, String value) {
    return new String(bytes, offset, 4, StandardCharsets.US_ASCII).equals(value);
  }

  private static IllegalArgumentException invalid() {
    return new IllegalArgumentException("Use a PCM16 WAV recording between 0.25 and 60 seconds, up to 4 MiB");
  }
}
