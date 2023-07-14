import 'dart:convert';

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
      options.headers.forEach(msg.addHeader);
    }

    if (requestBody) {
      final dynamic data = options.data;

      if (data is FormData) {
        if (data.fields.isNotEmpty) {
          msg.add('formDataFields:');
          Map.fromEntries(data.fields).forEach(msg.addHeader);
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
    Response response,
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
    Response response, {
    bool isError = false,
  }) {
    msg.addKV('uri', response.requestOptions.uri);
    if (responseHeader) {
      msg.addKV('statusCode', response.statusCode);
      if (response.isRedirect) {
        msg.addKV('redirect', response.realUri);
      }

      msg.add('headers:');
      response.headers.forEach((key, v) => msg.addKV(key, v.join('\r\n\t')));
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
    final dynamic objectData = data;
    if (objectData == null) {
      writeln('$objectData');

      return;
    }

    const encoder = JsonEncoder.withIndent('  ');

    final stringData = switch (objectData) {
      Map() => encoder.convert(objectData),
      String() => encoder.convert(jsonDecode(objectData)),
      _ => () {
          try {
            // ignore: avoid_dynamic_calls
            final dynamic jsonString = objectData.toJson();
            return encoder.convert(jsonString);
          } on Exception catch (_) {
            return json.toString();
          }
        }()
    };

    writeln(stringData);
  }

  void add(Object? v) {
    writeln('$v');
  }
}
