import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum EnvironmentType {
  development,
  production;

  bool get isDev => this == development;
  bool get isProd => this == production;
}

final class Environment {
  const Environment._({required this.baseUrl, required this.type});
  static Future<Environment> prod() async {
    const baseUrl = 'https://prod.com';
    const type = EnvironmentType.production;

    return const Environment._(baseUrl: baseUrl, type: type);
  }

  static Future<Environment> dev() async {
    const baseUrl = 'https://dev.com';
    const type = EnvironmentType.development;

    if (!kReleaseMode) {
      await dotenv.load(isOptional: true);

      return Environment._(
        baseUrl: dotenv.maybeGet('BASE_URL', fallback: baseUrl)!,
        type: type,
      );
    }

    return const Environment._(baseUrl: baseUrl, type: type);
  }

  final String baseUrl;
  final EnvironmentType type;
}
