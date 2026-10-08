package com.anajakmap.identity;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "accounts")
public class Account {
  @Id public String id;

  @Column(nullable = false, unique = true)
  public String email;

  public String displayName;
  public String legalVersion;
  public Instant legalAcceptedAt;

  @Column(nullable = false)
  public String passwordHash;

  @Convert(converter = org.hibernate.type.NumericBooleanConverter.class)
  public boolean verified;

  @Lob public String preferences = "{}";
  public Instant createdAt = Instant.now();
  @Version public long version;

  public Account() {}
}
