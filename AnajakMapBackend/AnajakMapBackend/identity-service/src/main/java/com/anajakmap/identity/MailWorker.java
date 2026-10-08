package com.anajakmap.identity;

import com.anajakmap.platform.*;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSenderImpl;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class MailWorker {
  private final JdbcTemplate jdbc;
  private final SecretVault vault;
  private final AuthDelivery config;
  private final JavaMailSenderImpl smtp;
  public MailWorker(JdbcTemplate jdbc, SecretVault vault, AuthDelivery config) {
    this.jdbc = jdbc;
    this.vault = vault;
    this.config = config;
    smtp = new JavaMailSenderImpl();
    smtp.setHost("smtp.gmail.com");
    smtp.setPort(587);
    smtp.setUsername(config.username);
    smtp.setPassword(config.password);
    var properties = smtp.getJavaMailProperties();
    properties.setProperty("mail.smtp.auth", "true");
    properties.setProperty("mail.smtp.starttls.enable", "true");
    properties.setProperty("mail.smtp.starttls.required", "true");
    properties.setProperty("mail.smtp.ssl.checkserveridentity", "true");
    properties.setProperty("mail.smtp.connectiontimeout", "10000");
    properties.setProperty("mail.smtp.timeout", "10000");
    properties.setProperty("mail.smtp.writetimeout", "10000");
    properties.setProperty("mail.debug", "false");
  }
  static String message(String kind, String code, String recipient, String linkBase) {
    String action = kind.equals("VERIFY") ? "verify your email" : "reset your password";
    String text = "Anajak Travel Companion\n\nUse this code to " + action + ": " + code
        + "\n\nThis code expires 15 minutes after it was requested. Use only the most recent email."
        + "\nIf you did not request this, ignore this message. Never share this code.\n";
    if (!linkBase.isBlank()) {
      String route = kind.equals("VERIFY") ? "verify" : "reset";
      text += "\nOpen Anajak: " + linkBase + "#" + route + "?email="
          + URLEncoder.encode(recipient, StandardCharsets.UTF_8) + "&code="
          + URLEncoder.encode(code, StandardCharsets.UTF_8) + "\n";
    }
    return text;
  }
  @Scheduled(fixedDelay = 30000)
  public void run() {
    jdbc.update("DELETE FROM mail_delivery WHERE expires_at<=SYSTIMESTAMP OR sent=1");
    if (!config.enabled()) return;
    var rows = jdbc.queryForList("SELECT id,recipient,kind,secret_value FROM mail_delivery WHERE sent=0 AND attempts<5 AND expires_at>SYSTIMESTAMP FETCH FIRST 10 ROWS ONLY");
    for (var row : rows) {
      String id = row.get("ID").toString();
      try {
        String recipient = row.get("RECIPIENT").toString();
        String kind = row.get("KIND").toString();
        String code = vault.decrypt(row.get("SECRET_VALUE").toString());
        if (config.gmail()) {
          var mail = new SimpleMailMessage();
          mail.setFrom(config.username);
          mail.setTo(recipient);
          mail.setSubject(kind.equals("VERIFY") ? "Verify your Anajak email" : "Reset your Anajak password");
          mail.setText(message(kind, code, recipient, config.linkBase));
          smtp.send(mail);
        } else {
          HttpClients.client(config.providerUrl).post().uri("/email")
              .header("Authorization", "Bearer " + config.providerKey)
              .header("Idempotency-Key", id)
              .body(Map.of("recipient", recipient, "template", kind, "code", code))
              .retrieve().toBodilessEntity();
        }
        jdbc.update("UPDATE mail_delivery SET sent=1 WHERE id=?", id);
      } catch (Exception e) {
        jdbc.update("UPDATE mail_delivery SET attempts=attempts+1 WHERE id=?", id);
        org.slf4j.LoggerFactory.getLogger(MailWorker.class).warn("mail_delivery_failed id={} type={}", id, e.getClass().getSimpleName());
      }
    }
  }
}
