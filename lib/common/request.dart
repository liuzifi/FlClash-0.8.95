import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/cupertino.dart';

class Request {
  late final Dio dio;
  late final Dio _clashDio;
  String? userAgent;

  Request() {
    dio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
    _clashDio = Dio();
    _clashDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (Uri uri) {
          client.userAgent = globalState.ua;
          return FlClashHttpOverrides.handleFindProxy(uri);
        };
        return client;
      },
    );
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    if (url.isFileUrl) {
      return _getFileResponseForUrl(url);
    }
    try {
      return await _clashDio.get<Uint8List>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
    } catch (e) {
      commonPrint.log('getFileResponseForUrl error ${e.toString()}');
      if (e is DioException) {
        if (e.type == DioExceptionType.unknown) {
          throw currentAppLocalizations.unknownNetworkError;
        } else if (e.type == DioExceptionType.badResponse) {
          throw currentAppLocalizations.networkException;
        }
        rethrow;
      }
      throw currentAppLocalizations.unknownNetworkError;
    }
  }

  Future<Response<String>> getTextResponseForUrl(String url) async {
    if (url.isFileUrl) {
      return _getTextResponseForFileUrl(url);
    }
    final response = await _clashDio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return response;
  }

  String _buildFilePath(Uri uri) {
    final segments =
        uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty && segments.first.contains(':')) {
      return segments.join('/');
    }
    final host = uri.host;
    if (host.isNotEmpty && host.toLowerCase() != 'localhost') {
      if (host.length == 1 && RegExp(r'^[a-zA-Z]$').hasMatch(host)) {
        return '$host:/${segments.join('/')}';
      }
      return '//$host/${segments.join('/')}';
    }
    return '/${segments.join('/')}';
  }

  Response<Uint8List> _buildBytesResponse({
    required String url,
    required Uint8List bytes,
    String? fileName,
  }) {
    final requestOptions = RequestOptions(path: url);
    final disposition = fileName == null
        ? null
        : "attachment; filename*=UTF-8''${Uri.encodeComponent(fileName)}";
    final headers = disposition == null
        ? null
        : Headers.fromMap({
            'content-disposition': [disposition],
          });
    return Response(
      requestOptions: requestOptions,
      data: bytes,
      statusCode: HttpStatus.ok,
      headers: headers,
    );
  }

  Future<Response<Uint8List>> _getFileResponseForUrl(String url) async {
    final uri = Uri.parse(url);
    final segments =
        uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty && uri.host.isEmpty) {
      throw Exception('Empty file path in file url: $url');
    }
    final filePath = _buildFilePath(uri);
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Local file not found: $filePath');
    }
    final bytes = await file.readAsBytes();
    return _buildBytesResponse(
      url: url,
      bytes: bytes,
      fileName: segments.lastOrNull,
    );
  }

  Future<Response<String>> _getTextResponseForFileUrl(String url) async {
    final uri = Uri.parse(url);
    final segments =
        uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty && uri.host.isEmpty) {
      throw Exception('Empty file path in file url: $url');
    }
    final filePath = _buildFilePath(uri);
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Local file not found: $filePath');
    }
    final content = await file.readAsString();
    final requestOptions = RequestOptions(path: url);
    return Response(
      requestOptions: requestOptions,
      data: content,
      statusCode: HttpStatus.ok,
    );
  }

  Future<MemoryImage?> getImage(String url) async {
    if (url.isEmpty) return null;
    final response = await dio.get<Uint8List>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null) return null;
    return MemoryImage(data);
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final response = await dio.get(
        'https://api.github.com/repos/$repository/releases/latest',
        options: Options(responseType: ResponseType.json),
      );
      if (response.statusCode != 200) return null;
      final data = response.data as Map<String, dynamic>;
      final remoteVersion = data['tag_name'];
      final version = globalState.packageInfo.version;
      final hasUpdate =
          utils.compareVersions(remoteVersion.replaceAll('v', ''), version) > 0;
      if (!hasUpdate) return null;
      return data;
    } catch (e) {
      commonPrint.log('checkForUpdate failed', logLevel: LogLevel.warning);
      return null;
    }
  }

  final Map<String, IpInfo Function(Map<String, dynamic>)> _ipInfoSources = {
    'https://ipwho.is': IpInfo.fromIpWhoIsJson,
    'https://api.myip.com': IpInfo.fromMyIpJson,
    'https://ipapi.co/json': IpInfo.fromIpApiCoJson,
    'https://ident.me/json': IpInfo.fromIdentMeJson,
    'http://ip-api.com/json': IpInfo.fromIpAPIJson,
    'https://api.ip.sb/geoip': IpInfo.fromIpSbJson,
    'https://ipinfo.io/json': IpInfo.fromIpInfoIoJson,
  };

  Future<Result<IpInfo?>> checkIp({CancelToken? cancelToken}) async {
    var failureCount = 0;
    final token = cancelToken ?? CancelToken();
    final futures = _ipInfoSources.entries.map((source) async {
      final Completer<Result<IpInfo?>> completer = Completer();
      void handleFailRes() {
        if (!completer.isCompleted && failureCount == _ipInfoSources.length) {
          completer.complete(Result.success(null));
        }
      }

      final future = dio
          .get<Map<String, dynamic>>(
            source.key,
            cancelToken: token,
            options: Options(responseType: ResponseType.json),
          )
          .timeout(const Duration(seconds: 10));
      future
          .then((res) {
            if (res.statusCode == HttpStatus.ok && res.data != null) {
              completer.complete(Result.success(source.value(res.data!)));
              return;
            }
            commonPrint.log('checkIp data empty', logLevel: LogLevel.info);
            failureCount++;
            handleFailRes();
          })
          .catchError((e) {
            failureCount++;
            if (e is DioException && e.type == DioExceptionType.cancel) {
              completer.complete(Result.error('cancelled'));
              return;
            }
            commonPrint.log('checkIp error $e', logLevel: LogLevel.warning);
            handleFailRes();
          });
      return completer.future;
    });
    final res = await Future.any(futures);
    token.cancel();
    return res;
  }
}

final request = Request();
