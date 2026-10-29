import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Incremental JPEG extraction with a strict buffer cap, including split markers.
class JpegFrames {
  final List<int> _buffer = [];
  static const maxBytes = 2 * 1024 * 1024;
  List<Uint8List> add(List<int> chunk) {
    if (chunk.length + _buffer.length > maxBytes) {
      _buffer.clear();
      throw const FormatException(
        'Camera frame exceeds 2 MiB. Lower the resolution.',
      );
    }
    _buffer.addAll(chunk);
    final frames = <Uint8List>[];
    while (true) {
      var start = -1;
      for (var i = 0; i + 1 < _buffer.length; i++) {
        if (_buffer[i] == 255 && _buffer[i + 1] == 216) {
          start = i;
          break;
        }
      }
      if (start < 0) {
        final last = _buffer.isNotEmpty ? _buffer.last : 0;
        _buffer.clear();
        if (last == 255) _buffer.add(last);
        break;
      }
      if (start > 0) _buffer.removeRange(0, start);
      var end = -1;
      for (var i = 2; i + 1 < _buffer.length; i++) {
        if (_buffer[i] == 255 && _buffer[i + 1] == 217) {
          end = i + 2;
          break;
        }
      }
      if (end < 0) break;
      frames.add(Uint8List.fromList(_buffer.sublist(0, end)));
      _buffer.removeRange(0, end);
    }
    return frames;
  }
}

class CameraService {
  CameraService(String streamUrl, String controlUrl, String token)
    : streamBase = _base(streamUrl),
      controlBase = _base(controlUrl),
      _authorization = 'Basic ${base64Encode(utf8.encode('camera:$token'))}';
  final Uri streamBase, controlBase;
  final String _authorization;
  http.Client? _streamClient;
  bool _closed = false;
  final _controlClient = http.Client();

  static Uri _base(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['', '/'].contains(uri.path)) {
      throw const FormatException(
        'Enter a camera base URL, e.g. http://192.168.1.50.',
      );
    }
    final octets = uri.host.split('.').map(int.tryParse).toList();
    final privateIp =
        octets.length == 4 &&
        octets.every((n) => n != null && n >= 0 && n <= 255) &&
        (octets[0] == 10 ||
            octets[0] == 192 && octets[1] == 168 ||
            octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31);
    if (uri.scheme == 'http' && !privateIp && !uri.host.endsWith('.local')) {
      throw const FormatException(
        'HTTP camera connections require a private LAN IP or .local hostname. Use HTTPS for a gateway.',
      );
    }
    return uri;
  }

  Stream<Uint8List> frames() async* {
    if (_closed) throw StateError('Camera is closed.');
    final client = http.Client();
    _streamClient?.close();
    _streamClient = client;
    try {
      final request = http.Request('GET', streamBase.resolve('/stream'));
      request.headers['Authorization'] = _authorization;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw StateError('Camera stream returned HTTP ${response.statusCode}.');
      }
      final parser = JpegFrames();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 10),
      )) {
        for (final frame in parser.add(chunk)) {
          yield frame;
        }
      }
      if (!_closed) {
        throw StateError('Camera disconnected. Reconnect to resume.');
      }
    } finally {
      client.close();
    }
  }

  Future<Uint8List> capture() async {
    final response = await _controlClient
        .get(
          controlBase.resolve('/capture'),
          headers: {'Authorization': _authorization},
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > JpegFrames.maxBytes ||
        !(response.headers['content-type'] ?? '').contains('image/jpeg')) {
      throw StateError('Snapshot failed (HTTP ${response.statusCode}).');
    }
    return response.bodyBytes;
  }

  Future<void> control(String name, int value) async {
    final uri = controlBase
        .resolve('/control')
        .replace(queryParameters: {'var': name, 'val': '$value'});
    final response = await _controlClient
        .get(uri, headers: {'Authorization': _authorization})
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('Camera control failed (HTTP ${response.statusCode}).');
    }
  }

  void close() {
    _closed = true;
    _streamClient?.close();
    _controlClient.close();
  }
}
