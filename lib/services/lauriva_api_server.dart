import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/llm_provider.dart';
import 'forensic/forensic_coordinator_service.dart';

/// Loopback HTTP API server on 127.0.0.1:7341 enabling external power integrations
/// (browser extensions, desktop automation, command-line pipes, CI/CD scripts).
typedef ClarivaApiServer = LaurivaApiServer;

class LaurivaApiServer {
  static const int defaultPort = 7341;
  final ForensicCoordinatorService _coordinator;
  HttpServer? _server;
  bool _isRunning = false;

  LaurivaApiServer({ForensicCoordinatorService? coordinator})
    : _coordinator = coordinator ?? ForensicCoordinatorService();

  bool get isRunning => _isRunning;
  int? get port => _server?.port;

  /// Starts the loopback HTTP server on [address]:[port].
  Future<bool> start({
    String host = '127.0.0.1',
    int port = defaultPort,
  }) async {
    if (_isRunning) return true;

    try {
      _server = await HttpServer.bind(host, port, shared: true);
      _isRunning = true;
      debugPrint('[LaurivaApiServer] Running at http://$host:$port/');

      _server!.listen(
        _handleRequest,
        onError: (e) {
          debugPrint('[LaurivaApiServer] Request error: $e');
        },
      );
      return true;
    } catch (e) {
      debugPrint('[LaurivaApiServer] Failed to bind server: $e');
      _isRunning = false;
      return false;
    }
  }

  /// Stops the server gracefully.
  Future<void> stop() async {
    if (!_isRunning) return;
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    debugPrint('[LaurivaApiServer] Stopped.');
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // Add CORS headers for browser extension access
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS',
    );
    request.response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization',
    );

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    try {
      if (request.method == 'GET' && path == '/health') {
        _respondJson(request.response, {
          'status': 'healthy',
          'engine': 'Lauriva Forensics Engine 3.5',
          'version': '3.5.0',
          'timestamp': DateTime.now().toIso8601String(),
        });
      } else if (request.method == 'GET' && path == '/models') {
        final providers = LlmProvider.allProviders
            .map(
              (p) => {
                'id': p.id,
                'name': p.name,
                'defaultModel': p.defaultModel,
                'models': p.models.map((m) => m.id).toList(),
              },
            )
            .toList();

        _respondJson(request.response, {'providers': providers});
      } else if (request.method == 'POST' && path == '/analyze') {
        final bodyStr = await utf8.decoder.bind(request).join();
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final text = body['text'] as String? ?? '';

        if (text.trim().isEmpty) {
          _respondError(
            request.response,
            'Text field is required',
            HttpStatus.badRequest,
          );
          return;
        }

        final report = await _coordinator.coordinate(text: text);
        _respondJson(request.response, report.toJson());
      } else if (request.method == 'POST' && path == '/humanize') {
        final bodyStr = await utf8.decoder.bind(request).join();
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final text = body['text'] as String? ?? '';

        if (text.trim().isEmpty) {
          _respondError(
            request.response,
            'Text field is required',
            HttpStatus.badRequest,
          );
          return;
        }

        _respondJson(request.response, {
          'status': 'success',
          'originalText': text,
          'message': 'Use StudioProvider / LLM service for active humanization transform.',
        });
      } else {
        _respondError(
          request.response,
          'Endpoint not found',
          HttpStatus.notFound,
        );
      }
    } catch (e) {
      _respondError(
        request.response,
        'Internal server error: $e',
        HttpStatus.internalServerError,
      );
    }
  }

  void _respondJson(
    HttpResponse response,
    Map<String, dynamic> jsonMap, [
    int status = HttpStatus.ok,
  ]) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(jsonMap));
    response.close();
  }

  void _respondError(HttpResponse response, String message, int statusCode) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({'error': message, 'code': statusCode}));
    response.close();
  }
}
