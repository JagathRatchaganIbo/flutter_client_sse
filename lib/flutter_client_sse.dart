import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SSEClient {
  final String url;
  final Map<String, String>? headers;

  http.Client? _client;
  StreamSubscription<String>? _subscription;
  StreamController<String>? _controller;

  SSEClient(this.url, {this.headers});

  /// Subscribe to the SSE stream
  Stream<String> subscribe() {
    _controller ??= StreamController<String>.broadcast(
      onListen: () {
        print("SSE broadcast: listener added");
        _connect();
      },
      onCancel: () async {
        print("SSE broadcast: listener removed");
        await unsubscribe();
      },
    );

    return _controller!.stream;
  }

  /// Internal method to connect to SSE endpoint
  Future<void> _connect() async {
    if (_subscription != null) {
      print("SSE already connected, skipping new connect");
      return;
    }
    _client = http.Client();
    final request = http.Request("GET", Uri.parse(url));
    if (headers != null) {
      request.headers.addAll(headers!);
    }

    try {
      final response = await _client!.send(request);
      if (response.statusCode != 200) {
        throw Exception("SSE failed with status ${response.statusCode}");
      }

      _subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
          if (line.startsWith("data:")) {
            final data = line.substring(5).trim();
            if (!_controller!.isClosed) {
              _controller!.add(data);
            }
          }
        },
        onError: (error, stack) {
          print("---ERROR--- $error");
          _retry();
        },
        onDone: () {
          print("---SSE DONE---");
          _retry();
        },
        cancelOnError: true,
      );
    } catch (e) {
      print("---ERROR connecting SSE--- $e");
      _retry();
    }
  }

  /// Retry with delay
  void _retry() {
    if (_controller == null || _controller!.isClosed) return;
    print("---RETRY CONNECTION---");
    Future.delayed(const Duration(seconds: 3), () {
      if (_controller != null && !_controller!.isClosed) {
        _connect();
      }
    });
  }

  /// Unsubscribe and close connection
  Future<void> unsubscribe() async {
    print("---UNSUBSCRIBE SSE---");
    await _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;

    if (_controller != null && !_controller!.isClosed) {
      await _controller!.close();
    }
    _controller = null;
  }
}
