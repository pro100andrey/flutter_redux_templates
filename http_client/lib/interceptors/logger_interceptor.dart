import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

final _logger = Logger('Http');

class LoggerInterceptor extends Interceptor {
  LoggerInterceptor({
    this.enableLogging = true,
    this.request = true,
    this.requestHeader = true,
    this.requestBody = true,
    this.responseHeader = true,
    this.responseBody = true,
    this.error = true,
  });

  bool enableLogging;

  /// Print request
  bool request;

  /// Print request header
  bool requestHeader;

  /// Print request data
  bool requestBody;

  /// Print [Response.data]
  bool responseBody;

  /// Print [Response.headers]
  bool responseHeader;

  /// Print error message
  bool error;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!enableLogging) {
      handler.next(options);
      return;
    }

    final msg = StringBuffer()
      ..add('*** Request ***')
      ..addKV('uri', options.uri);

    if (request) {
      msg
        ..addKV('method', options.method)
        ..addKV('responseType', options.responseType.toString())
        ..addKV('followRedirects', options.followRedirects)
        ..addKV('connectTimeout', options.connectTimeout)
        ..addKV('sendTimeout', options.sendTimeout)
        ..addKV('receiveTimeout', options.receiveTimeout)
        ..addKV(
          'receiveDataWhenStatusError',
          options.receiveDataWhenStatusError,
        )
        ..addKV('extra', options.extra);
    }

    if (requestHeader) {
      msg.add('headers:');
      options.headers.forEach(
        (key, v) => msg.addHeader(key, redact(key, v)),
      );
    }

    if (requestBody) {
      final dynamic data = options.data;

      if (data is FormData) {
        if (data.fields.isNotEmpty) {
          msg.add('formDataFields:');
          for (final MapEntry(:key, :value) in data.fields) {
            msg.addHeader(key, redact(key, value));
          }
        }

        if (data.files.isNotEmpty) {
          msg.add('formDataFiles:');
          Map.fromEntries(data.files).forEach(msg.addHeader);
        }
      } else {
        msg
          ..add('body:')
          ..addAsJson(data);
      }
    }
    _logger.fine(msg);
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    if (enableLogging) {
      final msg = StringBuffer()..add('*** Response ***');
      _printResponse(msg, response);
    }

    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (error && enableLogging) {
      final msg = StringBuffer()
        ..add('*** DioError ***:')
        ..add('uri: ${err.requestOptions.uri}')
        ..add('$err');
      if (err.response != null) {
        _printResponse(msg, err.response!, isError: true);
      }
    }

    handler.next(err);
  }

  void _printResponse(
    StringBuffer msg,
    Response<dynamic> response, {
    bool isError = false,
  }) {
    msg.addKV('uri', response.requestOptions.uri);
    if (responseHeader) {
      msg.addKV('statusCode', response.statusCode);
      if (response.isRedirect) {
        msg.addKV('redirect', response.realUri);
      }

      msg.add('headers:');
      response.headers.forEach(
        (key, v) => msg.addKV(key, redact(key, v.join('\r\n\t'))),
      );
    }
    if (responseBody) {
      msg
        ..add('body:')
        ..addAsJson(response.data);
    }
    isError ? _logger.warning(msg) : _logger.fine(msg);
  }
}

extension _StringBufferExt on StringBuffer {
  void addKV(String key, Object? v) {
    writeln('$key: $v');
  }

  void addHeader(String key, Object? v) {
    writeln('- $key: $v');
  }

  void addAsJson(Object? data) {
    writeln(formatBody(data));
  }

  void add(Object? v) {
    writeln('$v');
  }
}

/// A body as the log shows it: indented JSON when it is JSON, the text itself
/// when it is not, with every sensitive value replaced.
///
/// **This must not throw, whatever the body is**, because it runs inside a Dio
/// interceptor, and an interceptor that throws turns the request into a
/// failure: Dio catches the throw and completes the call with
/// `DioException(type: unknown)`. A log line was failing successful requests
/// three ways — a `text/plain` body went through `jsonDecode` (a
/// FormatException), a JSON *array* reached `d.toJson()` (a NoSuchMethodError,
/// an `Error`, which the `on Exception` around it let straight through), and
/// the fallback printed `json.toString()`, the codec, not the data. Hence
/// `on Object`, and the plain `'$data'` as the answer of last resort.
String formatBody(Object? data) {
  try {
    final Object? json = switch (data) {
      null => null,
      // Before `List()`: an upload's bytes are a List<int> too, and a log
      // line with a number per byte helps nobody.
      TypedData() => '<${data.lengthInBytes} bytes>',
      Map() || List() => data,
      String() => _tryJsonDecode(data) ?? data,
      // A request model: retrofit usually hands Dio its `toJson()` already,
      // but a hand-written call may pass the object itself.
      _ => (data as dynamic).toJson(),
    };
    if (json is String) {
      return json;
    }
    return _encoder.convert(_redactJson(json));
  } on Object {
    return '$data';
  }
}

/// [value], or a placeholder when [key] names a secret.
///
/// Headers and form fields go through here, and so does every key of a JSON
/// body. The log is written to the console in debug and wherever the app sends
/// its logs after that; a bearer token, a session cookie or the password of
/// the login request has no business in either. It matches by *name*, so a
/// `password` field is caught whether it arrives in a JSON body, a form, or a
/// custom header.
Object? redact(String key, Object? value) =>
    _sensitive.hasMatch(key) ? _redacted : value;

const _redacted = '<redacted>';

final _sensitive = RegExp(
  'authorization|cookie|password|passwd|secret|token|api[-_]?key',
  caseSensitive: false,
);

/// Unknown leaves (a DateTime, an enum) print as their `toString()` rather
/// than making `convert` throw.
const _encoder = JsonEncoder.withIndent('  ', _toEncodable);

Object? _toEncodable(Object? value) => '$value';

Object? _tryJsonDecode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

Object? _redactJson(Object? json) => switch (json) {
  Map() => {
    for (final MapEntry(:key, :value) in json.entries)
      '$key': redact('$key', _redactJson(value)),
  },
  List() => [for (final item in json) _redactJson(item)],
  _ => json,
};
