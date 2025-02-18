import 'package:postgres/postgres.dart';

import 'config.dart';

const String schemaName = 'groupscholar_review_capacity_hub';

class DbClient {
  DbClient(this._connection);

  final Connection _connection;

  static Future<DbClient> connect(DbConfig config) async {
    final connection = await Connection.open(
      config.toEndpoint(),
      settings: ConnectionSettings(
        sslMode: config.sslMode,
      ),
    );

    return DbClient(connection);
  }

  Future<List<ResultRow>> query(String sql, {Map<String, Object?>? parameters}) {
    return _connection.execute(
      Sql.named(sql),
      parameters: parameters ?? const <String, Object?>{},
    );
  }

  Future<void> close() {
    return _connection.close();
  }
}
