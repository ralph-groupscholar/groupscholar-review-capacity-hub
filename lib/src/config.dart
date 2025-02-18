import 'dart:io';

import 'package:postgres/postgres.dart';

class DbConfig {
  DbConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    required this.sslMode,
  });

  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final SslMode sslMode;

  static DbConfig fromEnv() {
    final host = _requiredEnv('GS_DB_HOST');
    final port = int.tryParse(_requiredEnv('GS_DB_PORT'));
    final database = _requiredEnv('GS_DB_NAME');
    final username = _requiredEnv('GS_DB_USER');
    final password = _requiredEnv('GS_DB_PASSWORD');
    final sslModeRaw = Platform.environment['GS_DB_SSLMODE'] ?? 'require';

    if (port == null) {
      throw FormatException('GS_DB_PORT must be an integer.');
    }

    return DbConfig(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      sslMode: _parseSslMode(sslModeRaw),
    );
  }

  Endpoint toEndpoint() {
    return Endpoint(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    );
  }
}

String _requiredEnv(String key) {
  final value = Platform.environment[key];
  if (value == null || value.trim().isEmpty) {
    throw StateError('Missing required environment variable: $key');
  }
  return value.trim();
}

SslMode _parseSslMode(String value) {
  switch (value.toLowerCase()) {
    case 'disable':
      return SslMode.disable;
    case 'require':
      return SslMode.require;
    case 'verify-full':
      return SslMode.verifyFull;
    default:
      throw FormatException('Unsupported GS_DB_SSLMODE value: $value');
  }
}
