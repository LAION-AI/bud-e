/// Local debug API server — allows remote control of BUD-E for testing.
/// Runs on localhost:8790, provides endpoints to send messages, take screenshots,
/// check status, upload files, etc.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../providers/chat_provider.dart';
import '../screens/memory_explorer_screen.dart';
import '../screens/wakeword_debug_screen.dart';
import 'debug_log.dart';

class DebugApiServer {
  HttpServer? _server;
  final ChatProvider _chat;
  final GlobalKey _repaintKey;
  final GlobalKey<NavigatorState> _navigatorKey;
  static const int _port = 8790;

  DebugApiServer(this._chat, this._repaintKey, this._navigatorKey);

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      debugLog(DebugSource.system, 'Debug API server on http://localhost:$_port');
      _server!.listen(_handleRequest);
    } catch (e) {
      debugLog(DebugSource.system, 'Debug API failed to start: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close();
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final path = req.uri.path;
    final params = req.uri.queryParameters;

    // CORS
    req.response.headers.add('Access-Control-Allow-Origin', '*');
    req.response.headers.add('Access-Control-Allow-Methods', 'GET, POST');

    try {
      switch (path) {
        case '/status':
          await _status(req);
        case '/messages':
          await _messages(req);
        case '/send':
          await _send(req, params);
        case '/send_with_files':
          await _sendWithFiles(req);
        case '/screenshot':
          await _screenshot(req);
        case '/agents':
          await _agents(req);
        case '/clear':
          await _clear(req);
        case '/files':
          await _listFiles(req);
        case '/images':
          await _listImages(req);
        case '/navigate':
          await _navigate(req, params);
        case '/go_back':
          _navigatorKey.currentState?.pop();
          _json(req, {'navigated': 'back'});
        case '/wakeword':
          final ww = _chat.wakeWordService;
          final action = params['action'];
          if (action == 'start') { ww.startListening(); }
          if (action == 'stop') { ww.stopListening(); }
          if (action == 'toggle') { _chat.toggleWakeWord(); }
          _json(req, {'ready': ww.isReady, 'listening': ww.isListening});
        case '/debug_log':
          await _debugLog(req, params);
        default:
          _json(req, {'error': 'Unknown endpoint', 'endpoints': [
            'GET /status - App state',
            'GET /messages - All messages',
            'GET /send?text=... - Send a message',
            'POST /send_with_files - Send with files (JSON body)',
            'GET /screenshot - Take screenshot (PNG)',
            'GET /agents - Agent task status',
            'GET /clear - Clear conversation',
            'GET /files - List workspace files',
            'GET /images - List registered images',
            'GET /debug_log?last=20 - Recent debug log',
          ]}, status: 404);
      }
    } catch (e) {
      _json(req, {'error': e.toString()}, status: 500);
    }
  }

  /// GET /status — app state overview
  Future<void> _status(HttpRequest req) async {
    _json(req, {
      'isLoading': _chat.isLoading,
      'isRecording': _chat.isRecording,
      'ttsEnabled': _chat.ttsEnabled,
      'messageCount': _chat.messages.length,
      'conversationId': _chat.conversation.id,
      'conversationTitle': _chat.conversation.title,
      'activeAgents': _chat.agentTasks.length,
      'registeredImages': _chat.imageRegistry.images.length,
      'workspacePath': _chat.workspacePath,
    });
  }

  /// GET /messages — all messages in current conversation
  Future<void> _messages(HttpRequest req) async {
    final msgs = _chat.messages.map((m) => {
      'id': m.id,
      'role': m.role.name,
      'content': m.content.length > 2000
          ? '${m.content.substring(0, 2000)}...(truncated)'
          : m.content,
      'timestamp': m.timestamp.toIso8601String(),
      'files': m.attachedFiles,
      'metadata': m.metadata,
    }).toList();
    _json(req, {'messages': msgs, 'count': msgs.length});
  }

  /// GET /send?text=Hello — send a text message
  Future<void> _send(HttpRequest req, Map<String, String> params) async {
    final text = params['text'] ?? '';
    if (text.isEmpty) {
      _json(req, {'error': 'Missing ?text= parameter'}, status: 400);
      return;
    }
    // Send asynchronously
    _chat.sendMessage(text);
    _json(req, {
      'sent': text,
      'messageCount': _chat.messages.length,
      'isLoading': true,
    });
  }

  /// POST /send_with_files — send message with file paths
  /// Body: {"text": "...", "files": ["path1", "path2"]}
  Future<void> _sendWithFiles(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final text = data['text'] as String? ?? '';
    final files = (data['files'] as List?)?.map((f) => f.toString()).toList() ?? [];

    if (files.isNotEmpty) {
      _chat.sendMessageWithFiles(text, files);
    } else {
      _chat.sendMessage(text);
    }
    _json(req, {'sent': text, 'files': files});
  }

  /// GET /screenshot — capture the app window as PNG
  Future<void> _screenshot(HttpRequest req) async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _json(req, {'error': 'Cannot find render boundary'}, status: 500);
        return;
      }
      final image = await boundary.toImage(pixelRatio: 1.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _json(req, {'error': 'Failed to encode PNG'}, status: 500);
        return;
      }
      req.response.headers.contentType = ContentType('image', 'png');
      req.response.add(byteData.buffer.asUint8List());
      await req.response.close();
    } catch (e) {
      _json(req, {'error': 'Screenshot failed: $e'}, status: 500);
    }
  }

  /// GET /agents — active agent tasks
  Future<void> _agents(HttpRequest req) async {
    final tasks = _chat.agentTasks.values.map((t) => {
      'id': t.id,
      'status': t.status.name,
      'instruction': t.instruction,
      'currentStep': t.currentStep,
      'maxSteps': t.maxSteps,
      'steps': t.steps,
      'generatedFiles': t.generatedFiles,
      'error': t.error,
    }).toList();
    _json(req, {'agents': tasks, 'count': tasks.length});
  }

  /// GET /clear — clear conversation
  Future<void> _clear(HttpRequest req) async {
    await _chat.clearConversation();
    _json(req, {'cleared': true});
  }

  /// GET /files — list workspace files
  Future<void> _listFiles(HttpRequest req) async {
    final dir = Directory(_chat.workspacePath);
    if (!await dir.exists()) {
      _json(req, {'files': [], 'path': _chat.workspacePath});
      return;
    }
    final entries = await dir.list().toList();
    final files = <Map<String, dynamic>>[];
    for (final e in entries) {
      if (e is File) {
        files.add({
          'name': e.uri.pathSegments.last,
          'path': e.path,
          'size': await e.length(),
        });
      }
    }
    _json(req, {'files': files, 'path': _chat.workspacePath});
  }

  /// GET /images — registered images
  Future<void> _listImages(HttpRequest req) async {
    final imgs = _chat.imageRegistry.images.map((i) => {
      'id': i.id,
      'filePath': i.filePath,
      'source': i.source,
      'prompt': i.prompt,
    }).toList();
    _json(req, {'images': imgs, 'count': imgs.length});
  }

  /// GET /debug_log?last=20 — recent debug entries
  Future<void> _debugLog(HttpRequest req, Map<String, String> params) async {
    final last = int.tryParse(params['last'] ?? '20') ?? 20;
    final entries = DebugLog.instance.entries;
    final recent = entries.length > last
        ? entries.sublist(entries.length - last)
        : entries;
    _json(req, {
      'entries': recent.map((e) => {
        'time': e.timestamp.toIso8601String().substring(11, 23),
        'source': e.sourceLabel,
        'message': e.message,
      }).toList(),
      'total': entries.length,
    });
  }

  /// GET /navigate?to=memory — navigate to a screen
  Future<void> _navigate(HttpRequest req, Map<String, String> params) async {
    final to = params['to'] ?? '';
    final nav = _navigatorKey.currentState;
    if (nav == null) {
      _json(req, {'error': 'No navigator'}, status: 500);
      return;
    }
    switch (to) {
      case 'memory':
        nav.push(MaterialPageRoute(builder: (_) => const MemoryExplorerScreen()));
        _json(req, {'navigated': 'memory'});
      case 'wakeword':
        nav.push(MaterialPageRoute(builder: (_) => const WakeWordDebugScreen()));
        _json(req, {'navigated': 'wakeword'});
      default:
        _json(req, {'error': 'Unknown screen: $to', 'available': ['memory', 'wakeword']}, status: 400);
    }
  }

  void _json(HttpRequest req, Map<String, dynamic> data, {int status = 200}) {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(data));
    req.response.close();
  }
}
