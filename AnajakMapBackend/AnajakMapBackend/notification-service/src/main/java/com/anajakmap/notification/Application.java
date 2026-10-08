package com.anajakmap.notification;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication(scanBasePackages = {"com.anajakmap.notification", "com.anajakmap.platform"})
@EnableScheduling
public class Application {
  public static void main(String[] args) {
    if (!com.anajakmap.platform.MigrationRunner.runIfRequested())
      SpringApplication.run(Application.class, args);
  }
}
