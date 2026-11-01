package com.anajakmap.aiguide;

import static org.junit.jupiter.api.Assertions.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;
import org.junit.jupiter.api.Test;

class VoiceAudioTest {
  static byte[] wave(int seconds) {
    int dataBytes = 16000 * 2 * seconds;
    var b = ByteBuffer.allocate(44 + dataBytes).order(ByteOrder.LITTLE_ENDIAN);
    b.put("RIFF".getBytes()).putInt(36 + dataBytes).put("WAVEfmt ".getBytes()).putInt(16)
        .putShort((short)1).putShort((short)1).putInt(16000).putInt(32000)
        .putShort((short)2).putShort((short)16).put("data".getBytes()).putInt(dataBytes);
    return b.array();
  }
  @Test void acceptsRealPcmBoundaries() {
    assertDoesNotThrow(() -> VoiceAudio.validate(wave(1), "audio/wav"));
    assertDoesNotThrow(() -> VoiceAudio.validate(wave(60), "audio/wav"));
  }
  @Test void rejectsLongTruncatedSpoofedAndEmptyRecordings() {
    assertThrows(IllegalArgumentException.class, () -> VoiceAudio.validate(wave(61), "audio/wav"));
    assertThrows(IllegalArgumentException.class, () -> VoiceAudio.validate(wave(0), "audio/wav"));
    assertThrows(IllegalArgumentException.class, () -> VoiceAudio.validate(wave(1), "audio/mpeg"));
    assertThrows(IllegalArgumentException.class, () -> VoiceAudio.validate(Arrays.copyOf(wave(1), 60), "audio/wav"));
    var bytes = wave(1); bytes[0] = 'X';
    assertThrows(IllegalArgumentException.class, () -> VoiceAudio.validate(bytes, "audio/wav"));
  }
  @Test void rejectsCompressedHeaderAndInconsistentByteRate() {
    var bytes = wave(1); bytes[20] = 3;
    assertThrows(IllegalArgumentException.class, () -> VoiceAudio.validate(bytes, "audio/wav"));
    bytes[20] = 1; bytes[29] = 0;
    assertThrows(IllegalArgumentException.class, () -> VoiceAudio.validate(bytes, "audio/wav"));
  }
}
