library flutter_client_sse;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:http/http.dart' as http;
part 'sse_event_model.dart';

/// A client for subscribing to Server-Sent Events (SSE).
class SSEClient {
  static http.Client? _client;
  static StreamController<SSEModel>? _controller;
  static StreamSubscription<String>? _subscription;

  static Stream<SSEModel> get stream {
    _controller ??= StreamController<SSEModel>.broadcast(
      onListen: () => print("SSE broadcast: listener added"),
      onCancel: () {
        print("SSE broadcast: listener removed");
        if (!_controller!.hasListener) {
          _controller?.close();
          _controller = null;
        }
      },
    );
    return _controller!.stream;
  }

  static Stream<SSEModel> subscribeToSSE({
    required SSERequestType method,
    required String url,
    required Map<String, String> header,
    Map<String, dynamic>? body,
  }) {
    // Cleanup previous client if exists
    _client?.close();
    _client = http.Client();

    // Only create controller if it doesn't exist
    _controller ??= StreamController<SSEModel>.broadcast(
      onListen: () => print("SSE broadcast: listener added"),
      onCancel: () {
        print("SSE broadcast: listener removed");
        if (!_controller!.hasListener) {
          _controller?.close();
          _controller = null;
        }
      },
    );

    var lineRegex = RegExp(r'^([^:]*)(?::)?(?: )?(.*)?$');
    var currentSSEModel = SSEModel(data: '', id: '', event: '');

    _listenSSE(method, url, header, body, lineRegex, currentSSEModel);

    return _controller!.stream;
  }

  static void _listenSSE(
      SSERequestType method,
      String url,
      Map<String, String> header,
      Map<String, dynamic>? body,
      RegExp lineRegex,
      SSEModel currentSSEModel) async {
    try {
      var request = http.Request(
        method == SSERequestType.GET ? "GET" : "POST",
        Uri.parse(url),
      );

      header.forEach((key, value) {
        request.headers[key] = value;
      });

      if (body != null) {
        request.body = jsonEncode(body);
      }

      var response = await _client!.send(request);

      // Cancel old subscription if any
      await _subscription?.cancel();

      _subscription = response.stream
          .transform(Utf8Decoder())
          .transform(LineSplitter())
          .listen((dataLine) {
        if (dataLine.isEmpty) {
          _controller?.add(currentSSEModel);
          currentSSEModel = SSEModel(data: '', id: '', event: '');
          return;
        }
        Match? match = lineRegex.firstMatch(dataLine);
        if (match == null) return;

        var field = match.group(1);
        if (field == null || field.isEmpty) return;

        var value = field == 'data'
            ? dataLine.substring(5)
            : (match.group(2) ?? '');

        switch (field) {
          case 'event':
            currentSSEModel.event = value;
            break;
          case 'data':
            currentSSEModel.data =
                (currentSSEModel.data ?? '') + value + '\n';
            break;
          case 'id':
            currentSSEModel.id = value;
            break;
          default:
            print("---ERROR--- $dataLine");
            _retryConnection(
                method: method, url: url, header: header, body: body);
        }
      }, onError: (e, s) {
        print("---ERROR--- $e");
        _retryConnection(
            method: method, url: url, header: header, body: body);
      }, onDone: () {
        print("---SSE DONE---");
        _retryConnection(
            method: method, url: url, header: header, body: body);
      });
    } catch (e) {
      print("---ERROR--- $e");
      _retryConnection(
          method: method, url: url, header: header, body: body);
    }
  }

  static void _retryConnection({
    required SSERequestType method,
    required String url,
    required Map<String, String> header,
    Map<String, dynamic>? body,
  }) {
    print('---RETRY CONNECTION---');
    Future.delayed(const Duration(seconds: 5), () {
      if (_controller != null && !_controller!.isClosed) {
        subscribeToSSE(method: method, url: url, header: header, body: body);
      } else {
        print("---SKIP RETRY: controller closed---");
      }
    });
  }

  static void unsubscribeFromSSE() async {
    print("---UNSUBSCRIBE SSE---");
    await _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
    await _controller?.close();
    _controller = null;
  }
}


