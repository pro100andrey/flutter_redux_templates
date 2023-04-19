import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

final _logger = Logger('Retrofit');

class LoggerInterceptor extends Interceptor {
  LoggerInterceptor({
    this.request = true,
    this.requestHeader = true,
    this.requestBody = false,
    this.responseHeader = true,
    this.responseBody = false,
    this.error = true,
  });

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
        msg.add('formDataFields:');
        Map.fromEntries(data.fields).forEach(msg.addHeader);
        msg.add('formDataFiles:');
        Map.fromEntries(data.files).forEach(msg.addHeader);
      } else {
        msg
          ..add('body:')
          ..addAsJson(options.data);
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
    final msg = StringBuffer()..add('*** Response ***');
    _printResponse(msg, response);
    handler.next(response);
  }

  @override
  Future<void> onError(DioError err, ErrorInterceptorHandler handler) async {
    if (error) {
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
    final json = data;
    if (json == null) {
      writeln('$json');

      return;
    }

    const encoder = JsonEncoder.withIndent('  ');
    String result;
    if (json is Map) {
      result = encoder.convert(json);
    } else if (json is String) {
      try {
        final dynamic object =
            json.isEmpty ? <String, dynamic>{} : jsonDecode(json);
        result = encoder.convert(object);
      } on Exception {
        result = json;
      }
    } else {
      result = json.toString();
    }

    writeln(result);
  }

  void add(Object? v) {
    writeln('$v');
  }
}
