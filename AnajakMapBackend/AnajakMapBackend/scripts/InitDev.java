import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;

/** First-run local credentials, generated without printing secret material. */
public final class InitDev {
  private static final SecureRandom RANDOM = new SecureRandom();
  private static byte[] random(int size) {
    byte[] bytes = new byte[size];
    RANDOM.nextBytes(bytes);
    return bytes;
  }
  private static String hex(int size) {
    return HexFormat.of().withUpperCase().formatHex(random(size));
  }
  public static void main(String[] args) throws Exception {
    Path target = Path.of(args.length == 0 ? ".env" : args[0]);
    if (Files.exists(target)) throw new IllegalStateException(".env already exists; refusing to overwrite.");
    var generator = KeyPairGenerator.getInstance("RSA");
    generator.initialize(3072, RANDOM);
    var keys = generator.generateKeyPair();
    var values = new LinkedHashMap<String, String>();
    values.put("ORACLE_PASSWORD", hex(24));
    values.put("REDIS_PASSWORD", hex(24));
    values.put("RABBIT_USER", "anajak");
    values.put("RABBIT_PASSWORD", hex(24));
    values.put("OBJECT_ACCESS_KEY", "anajak-local");
    values.put("OBJECT_SECRET_KEY", hex(24));
    values.put("SERVICE_TOKEN", hex(32));
    values.put("DATA_ENCRYPTION_KEY", Base64.getEncoder().encodeToString(random(32)));
    values.put("JWT_PUBLIC_KEY", Base64.getEncoder().encodeToString(keys.getPublic().getEncoded()));
    values.put("JWT_PRIVATE_KEY", Base64.getEncoder().encodeToString(keys.getPrivate().getEncoded()));
    for (String service : List.of("IDENTITY", "TRIP", "AI_GUIDE", "DISCOVERY", "EXPENSE",
        "RESERVATION", "JOURNAL", "NOTIFICATION", "GATEWAY")) {
      values.put(service + "_DB_PASSWORD", hex(24));
      values.put(service + "_APP_PASSWORD", hex(24));
    }
    // CREATE_NEW prevents accidental replacement even if another process races.
    try (var writer = Files.newBufferedWriter(target, StandardCharsets.UTF_8,
        StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
      for (var value : values.entrySet()) {
        writer.write(value.getKey() + "=" + value.getValue());
        writer.newLine();
      }
    }
    System.out.println("Created local development credentials in ignored .env. Existing databases require their original credentials.");
  }
}
