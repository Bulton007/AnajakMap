package com.anajakmap.expense;

import com.anajakmap.platform.*;
import jakarta.validation.*;
import jakarta.validation.constraints.*;
import java.math.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/expenses")
public class ExpenseApi {
  private final JdbcTemplate jdbc;
  private final Changes changes;
  private final TripAccess access;
  private final TransactionTemplate tx;

  public ExpenseApi(JdbcTemplate j, Changes c, TripAccess a, PlatformTransactionManager t) {
    jdbc = j;
    changes = c;
    access = a;
    tx = new TransactionTemplate(t);
  }

  public record Budget(
      @NotBlank String tripId,
      @DecimalMin("0.01") @Digits(integer = 12, fraction = 2) @NotNull BigDecimal amount,
      @Pattern(regexp = "[A-Z]{3}") @NotNull String currency,
      long version) {}

  public record Expense(
      @NotBlank String tripId,
      @NotBlank @Size(max = 200) String description,
      @NotNull @DecimalMin("0.01") @Digits(integer = 12, fraction = 2) BigDecimal amount,
      @NotNull @Pattern(regexp = "[A-Z]{3}") String currency,
      @NotEmpty @Size(max = 100) Map<String, @DecimalMin("0.00") @NotNull BigDecimal> splits,
      String receiptId) {}

  @PutMapping("/budget")
  public Object budget(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @Valid @RequestBody Budget r) {
    access.require(r.tripId, bearer, true);
    Currency.getInstance(r.currency);
    return tx.execute(
        s -> {
          int n =
              jdbc.update(
                  "UPDATE budgets SET amount=?,currency=?,version=version+1,updated_at=CURRENT_TIMESTAMP"
                      + " WHERE trip_id=? AND version=?",
                  r.amount,
                  r.currency,
                  r.tripId,
                  r.version);
          if (n == 0) {
            if (r.version != 0
                || jdbc.queryForObject(
                        "SELECT COUNT(*) FROM budgets WHERE trip_id=?", Integer.class, r.tripId)
                    > 0) throw Api.conflict();
            jdbc.update(
                "INSERT INTO budgets(trip_id,amount,currency,version) VALUES(?,?,?,1)",
                r.tripId,
                r.amount,
                r.currency);
          }
          changes.record(
              jwt.getSubject(),
              "budget.updated",
              r.tripId,
              Map.of("amount", r.amount, "currency", r.currency));
          return Map.of("tripId", r.tripId, "version", r.version + 1);
        });
  }

  @PostMapping
  public Object add(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestHeader("Idempotency-Key") String key,
      @Valid @RequestBody Expense r) {
    access.require(r.tripId, bearer, true);
    Currency.getInstance(r.currency);
    if (!access.members(r.tripId, bearer).containsAll(r.splits.keySet())) throw Api.denied();
    BigDecimal sum = r.splits.values().stream().reduce(BigDecimal.ZERO, BigDecimal::add);
    if (sum.compareTo(r.amount) != 0 || r.splits.values().stream().anyMatch(v -> v.scale() > 2))
      throw new IllegalArgumentException("Splits must equal expense");
    return tx.execute(
        s -> {
          var prior = changes.prior(jwt.getSubject(), key, "expense.create", r);
          if (prior.isPresent()) return parse(prior.get());
          if (r.receiptId != null
              && jdbc.queryForObject(
                      "SELECT COUNT(*) FROM receipts WHERE id=? AND trip_id=? AND owner_id=?",
                      Integer.class,
                      r.receiptId,
                      r.tripId,
                      jwt.getSubject())
                  != 1) throw Api.denied();
          String id = UUID.randomUUID().toString();
          jdbc.update(
              "INSERT INTO expenses(id,trip_id,actor_id,description,amount,currency,receipt_id)"
                  + " VALUES(?,?,?,?,?,?,?)",
              id,
              r.tripId,
              jwt.getSubject(),
              r.description,
              r.amount,
              r.currency,
              r.receiptId);
          if (r.receiptId != null)
            jdbc.update(
                "UPDATE receipts SET status='CONFIRMED',version=version+1 WHERE id=?", r.receiptId);
          r.splits.forEach(
              (member, amount) ->
                  jdbc.update(
                      "INSERT INTO expense_splits(expense_id,account_id,amount) VALUES(?,?,?)",
                      id,
                      member,
                      amount));
          changes.record(
              jwt.getSubject(),
              "expense.created",
              id,
              Map.of("tripId", r.tripId, "amount", r.amount, "currency", r.currency));
          var result = Map.of("id", id, "version", 0);
          changes.remember(jwt.getSubject(), key, "expense.create", r, result);
          return result;
        });
  }

  @GetMapping
  public Object list(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestParam String tripId,
      @RequestParam(defaultValue = "0") int page,
      @RequestParam(defaultValue = "20") int size,
      @RequestParam(defaultValue = "created_at") String sort) {
    access.require(tripId, bearer, false);
    if (page < 0 || size < 1 || size > 100 || !Set.of("created_at", "amount").contains(sort))
      throw new IllegalArgumentException();
    return jdbc.queryForList(
        "SELECT id,description,amount,currency,created_at,version FROM expenses WHERE trip_id=?"
            + " ORDER BY "
            + sort
            + " DESC OFFSET ? ROWS FETCH NEXT ? ROWS ONLY",
        tripId,
        page * size,
        size);
  }

  @GetMapping("/summary")
  public Object summary(
      @RequestHeader("Authorization") String bearer, @RequestParam String tripId) {
    access.require(tripId, bearer, false);
    return Map.of(
        "budgets",
        jdbc.queryForList("SELECT amount,currency,version FROM budgets WHERE trip_id=?", tripId),
        "spentByCurrency",
        jdbc.queryForList(
            "SELECT currency,SUM(amount) AS total FROM expenses WHERE trip_id=? GROUP BY currency",
            tripId));
  }

  @GetMapping("/{id}/splits")
  public Object splits(@PathVariable String id, @RequestHeader("Authorization") String bearer) {
    String trip = jdbc.queryForObject("SELECT trip_id FROM expenses WHERE id=?", String.class, id);
    access.require(trip, bearer, false);
    return jdbc.queryForList("SELECT account_id,amount FROM expense_splits WHERE expense_id=?", id);
  }

  private Object parse(String s) {
    try {
      return new com.fasterxml.jackson.databind.ObjectMapper().readValue(s, Map.class);
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }
}
