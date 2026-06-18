import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart';

class AirgappedHttpClient implements Client {
  AirgappedHttpClient._(this._logFile);

  static AirgappedHttpClient? _instance;

  static final Future<Response> _responseOk = Future.value(Response('', 200));
  static final Future<String> _string = Future.value('');
  static final Future<Uint8List> _intList = Future.value(Uint8List(0));
  static const String _eventIdKey = 'event_id';

  final RandomAccessFile _logFile;

  static Future<AirgappedHttpClient> initialize(String logPath) async {
    if (_instance != null) {
      return _instance!;
    }

    final file = File(logPath);
    final randomAccessFile = await file.open(mode: FileMode.append);
    _instance = AirgappedHttpClient._(randomAccessFile);
    return _instance!;
  }

  factory AirgappedHttpClient() {
    if (_instance == null) {
      throw StateError(
        'AirgappedHttpClient has not been initialized. Call AirgappedHttpClient.initialize(logPath) first.',
      );
    }

    return _instance!;
  }

  @override
  void close() {
    _logFile.close();
  }

  @override
  Future<Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _responseOk;

  @override
  Future<Response> get(url, {Map<String, String>? headers}) => _responseOk;

  @override
  Future<Response> head(url, {Map<String, String>? headers}) => _responseOk;

  @override
  Future<Response> patch(
    url, {
    Map<String, String>? headers,
    body,
    Encoding? encoding,
  }) {
    inspect(body);
    return _responseOk;
  }

  @override
  Future<Response> post(
    url, {
    Map<String, String>? headers,
    body,
    Encoding? encoding,
  }) {
    inspect(body);
    return _responseOk;
  }

  @override
  Future<Response> put(
    url, {
    Map<String, String>? headers,
    body,
    Encoding? encoding,
  }) {
    inspect(body);
    return _responseOk;
  }

  @override
  Future<String> read(url, {Map<String, String>? headers}) => _string;

  @override
  Future<Uint8List> readBytes(url, {Map<String, String>? headers}) => _intList;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final bodyString = utf8.decode(bytes);
    final List<String> jsonChunks = bodyString.split('\n');
    final bodyStringCombined = "[${jsonChunks.join(",")}]";
    final bodyJson = jsonDecode(bodyStringCombined);

    final logData = {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'headers': request.headers,
      'method': request.method,
      'body': bytes,
      'url': request.url.toString(),
    };

    await _logFile.writeString('${jsonEncode(logData)}\n');
    List<List<int>> eventResponses = [];

    for (var event in bodyJson) {
      if (!event.containsKey(_eventIdKey)) {
        continue;
      }
      final eventId = event[_eventIdKey];

      eventResponses.add(_EventResponse(eventId).toInts());
    }

    Stream<List<int>> eventStream = Stream.fromIterable(eventResponses);

    return StreamedResponse(eventStream, 200);
  }
}

class _EventResponse {
  final String id;

  _EventResponse(this.id);

  Map<String, dynamic> toJson() => {'id': id};

  List<int> toInts() => jsonEncode(toJson()).codeUnits;
}
