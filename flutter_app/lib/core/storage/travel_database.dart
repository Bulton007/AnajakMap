import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import '../network/api_client.dart';

/// Explicit SQL tables keep cached reads separate from durable, reviewable edits.
class TravelDatabase extends GeneratedDatabase {
  TravelDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'anajak_connected',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE cache (scope TEXT NOT NULL, key TEXT NOT NULL, payload TEXT NOT NULL, saved_at TEXT NOT NULL, PRIMARY KEY(scope,key))',
      );
      await customStatement(
        "CREATE TABLE operations (id TEXT PRIMARY KEY, scope TEXT NOT NULL, kind TEXT NOT NULL, entity TEXT NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'queued', error TEXT, created_at TEXT NOT NULL)",
      );
    },
  );
  Future<void> cache(
    String scope,
    String key,
    Object? value,
  ) => customStatement(
    'INSERT OR REPLACE INTO cache(scope,key,payload,saved_at) VALUES(?,?,?,?)',
    [scope, key, jsonEncode(value), DateTime.now().toUtc().toIso8601String()],
  );
  Future<Json?> cached(String scope, String key) async {
    final rows = await customSelect(
      'SELECT payload,saved_at FROM cache WHERE scope=? AND key=?',
      variables: [Variable(scope), Variable(key)],
    ).get();
    if (rows.isEmpty) {
      return null;
    }
    return {
      'data': jsonDecode(rows.first.read<String>('payload')),
      'savedAt': rows.first.read<String>('saved_at'),
    };
  }

  Future<List<Json>> cachedEntries(String scope, String prefix) async =>
      (await customSelect(
            'SELECT key,payload,saved_at FROM cache WHERE scope=? AND key LIKE ? ORDER BY saved_at DESC',
            variables: [Variable(scope), Variable('$prefix%')],
          ).get())
          .map(
            (r) => {
              'key': r.read<String>('key'),
              'data': jsonDecode(r.read<String>('payload')),
              'savedAt': r.read<String>('saved_at'),
            },
          )
          .toList();
  Future<void> queue(
    String scope,
    String id,
    String kind,
    String entity,
    Json body,
  ) async {
    if (!['trip', 'expense', 'journal'].contains(kind)) {
      throw ArgumentError('This operation cannot be replayed offline');
    }
    await customStatement(
      'INSERT INTO operations(id,scope,kind,entity,payload,created_at) VALUES(?,?,?,?,?,?)',
      [
        id,
        scope,
        kind,
        entity,
        jsonEncode(body),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<List<Json>> pending(String scope) async =>
      (await customSelect(
            'SELECT * FROM operations WHERE scope=? ORDER BY created_at',
            variables: [Variable(scope)],
          ).get())
          .map(
            (r) => {...r.data, 'body': jsonDecode(r.read<String>('payload'))},
          )
          .toList();
  Future<void> mark(String scope, String id, String state, [String? error]) =>
      customStatement(
        'UPDATE operations SET state=?,error=? WHERE scope=? AND id=?',
        [state, error, scope, id],
      );
  Future<void> remove(String scope, String id) => customStatement(
    'DELETE FROM operations WHERE scope=? AND id=?',
    [scope, id],
  );
  Future<void> clear(String scope) => transaction(() async {
    await customStatement('DELETE FROM cache WHERE scope=?', [scope]);
    await customStatement('DELETE FROM operations WHERE scope=?', [scope]);
  });
  Future<void> pruneCache(
    String scope,
    String prefix,
    int keep,
  ) => customStatement(
    'DELETE FROM cache WHERE scope=? AND key LIKE ? AND key NOT IN '
    '(SELECT key FROM cache WHERE scope=? AND key LIKE ? ORDER BY saved_at DESC LIMIT ?)',
    [scope, '$prefix%', scope, '$prefix%', keep],
  );
}
