import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/app_theme.dart';
import '../services/camera_service.dart';
import '../services/gill_analysis_service.dart';
import '../services/firebase_service.dart';
import '../services/demo_session.dart';
import '../widgets/soft_ui.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.canSave});
  final bool canSave;
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final _stream = TextEditingController(text: 'http://esp32cam.local'),
      _control = TextEditingController(text: 'http://esp32cam.local:81'),
      _token = TextEditingController(),
      _sample = TextEditingController();
  CameraService? _camera;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _demoTimer, _flashTimer;
  Uint8List? _frame, _snapshot;
  GillAnalysis? _analysis;
  String? _message;
  bool _busy = false, _flash = false, _demoConnected = false, _saved = false;
  int _resolution = 8, _ticks = 0;
  int _controlRevision = 0;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DemoSession? _session;
  bool get _demo => _session?.enabled == true;
  bool get _connected => _demoConnected || _camera != null;
  (int, int) get _size => switch (_resolution) {
    5 => (320, 240),
    9 => (800, 600),
    _ => (640, 480),
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = DemoScope.maybeOf(context);
    if (_demo && _sample.text.isEmpty) _sample.text = 'DEMO-GILLS-001';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _disconnect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _camera?.close();
    _demoTimer?.cancel();
    _flashTimer?.cancel();
    for (final c in [_stream, _control, _token, _sample]) {
      c.dispose();
    }
    super.dispose();
  }

  void _disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _camera?.close();
    _camera = null;
    _demoTimer?.cancel();
    _flashTimer?.cancel();
    if (mounted) {
      setState(() {
        _frame = null;
        _demoConnected = false;
        _flash = false;
      });
    }
  }

  void _renderDemo() {
    final (width, height) = _size;
    _frame = _session!.cameraFrame(width: width, height: height, flash: _flash);
  }

  Future<void> _open() async {
    if (_connected) return;
    if (_demo) {
      _demoConnected = true;
      _renderDemo();
      _demoTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _ticks++);
      });
      return;
    }
    if (_token.text.length < 16) {
      throw const FormatException(
        'Enter the camera password (at least 16 characters) to connect hardware.',
      );
    }
    final camera = CameraService(_stream.text, _control.text, _token.text);
    _camera = camera;
    try {
      await camera.control('flash', 0);
      if (!mounted || _camera != camera) return;
      _subscription = camera.frames().listen(
        (bytes) {
          if (!mounted) return;
          final now = DateTime.now();
          if (now.difference(_lastFrame).inMilliseconds < 100) return;
          _lastFrame = now;
          setState(() => _frame = bytes);
        },
        onError: (Object error) {
          if (mounted) {
            _disconnect();
            setState(
              () => _message =
                  'Stream unavailable: $error. Check camera power, Wi-Fi and credentials, then reconnect.',
            );
          }
        },
      );
    } catch (_) {
      _disconnect();
      rethrow;
    }
  }

  Future<void> _work(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _message = 'Operation failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _controlRevision++;
        });
      }
    }
  }

  Future<void> _analyze(Uint8List bytes) async {
    final jpeg = await compute(prepareGillSnapshot, bytes);
    if (!mounted) return;
    setState(() {
      _snapshot = jpeg;
      _analysis = null;
      _saved = false;
    });
    final result = await compute(analyzeGills, jpeg);
    if (mounted) setState(() => _analysis = result);
  }

  Future<void> _capture() async {
    await _open();
    if (!mounted) return;
    final bytes = _demo ? _frame! : await _camera!.capture();
    await _analyze(bytes);
  }

  Future<void> _save() async {
    if (!_demo && !widget.canSave) {
      showNotice(
        context,
        'An approved Inspector role is required to save cloud analyses. You can still capture and analyze locally.',
      );
      return;
    }
    if (_saved) {
      showNotice(
        context,
        'This inspection has already been saved. Capture another image to create a new inspection.',
      );
      return;
    }
    if (_analysis == null) await _capture();
    if (!mounted || _analysis == null) return;
    final id = _sample.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id)) {
      throw const FormatException(
        'Enter a sample ID with 1–100 letters, numbers, underscores or hyphens.',
      );
    }
    if (_demo) {
      _session!.saveAnalysis(id, _analysis!);
    } else {
      await FirebaseService.uploadAnalysis(
        sampleId: id,
        imageBytes: _snapshot!,
        fileName: 'gills.jpg',
        meanHue: _analysis!.hue,
        classification: _analysis!.classification,
        hsvMetrics: {
          'meanSaturation': _analysis!.saturation,
          'meanValue': _analysis!.value,
          'redFraction': _analysis!.redFraction,
          'usableFraction': _analysis!.usableFraction,
        },
      );
    }
    if (mounted) {
      setState(() {
        _saved = true;
        _message = _demo
            ? 'Demo inspection saved to session history. Nothing was uploaded.'
            : 'Image and analysis saved to cloud.';
      });
    }
  }

  Future<void> _setFlash(bool value) async {
    await _open();
    if (!_demo) await _camera!.control('flash', value ? 1 : 0);
    if (!mounted) return;
    setState(() {
      _flash = value;
      if (_demo) _renderDemo();
    });
    _flashTimer?.cancel();
    if (value) {
      _flashTimer = Timer(const Duration(seconds: 30), () {
        if (mounted) {
          setState(() {
            _flash = false;
            if (_demo && _connected) _renderDemo();
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Camera & gill analysis',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          _demo
              ? 'DEMO · Synthetic color target, simulated stream and controls.'
              : 'ESP32-CAM · live MJPEG and local HSV inspection',
        ),
        const SizedBox(height: 24),
        SoftPanel(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 720,
                  maxHeight: 420,
                ),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: ColoredBox(
                      color: AppColors.navyDeep,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_frame != null)
                            Image.memory(
                              _frame!,
                              gaplessPlayback: true,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Center(
                                child: Text(
                                  'Invalid camera frame',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            )
                          else
                            const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.videocam_outlined,
                                    color: AppColors.aqua,
                                    size: 48,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Connect to start viewing',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          if (_frame != null)
                            Center(
                              child: FractionallySizedBox(
                                widthFactor: 200 / _size.$1,
                                heightFactor: 200 / _size.$2,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: AppColors.mint,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: 10,
                            left: 10,
                            right: 10,
                            child: Text(
                              _demo
                                  ? 'SIMULATED CALIBRATION TARGET · ${_connected ? 'FRAME $_ticks' : 'OFFLINE'}'
                                  : _connected
                                  ? 'CAMERA CONNECTED'
                                  : 'CAMERA OFFLINE',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SoftButton(
                    label: _connected ? 'Disconnect' : 'Connect stream',
                    icon: Icons.wifi,
                    primary: true,
                    busy: _busy,
                    onPressed: () {
                      if (_busy) return;
                      if (_connected) {
                        _disconnect();
                      } else {
                        _work(_open);
                      }
                    },
                  ),
                  SoftButton(
                    label: 'Capture & analyze',
                    icon: Icons.camera_alt_outlined,
                    busy: _busy,
                    onPressed: () => _work(_capture),
                  ),
                  SoftButton(
                    label: 'Refresh camera',
                    icon: Icons.refresh,
                    busy: _busy,
                    onPressed: () => _work(() async {
                      _disconnect();
                      await _open();
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SoftPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 24,
                runSpacing: 20,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: SoftField(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('$_resolution-$_controlRevision'),
                        isExpanded: true,
                        initialValue: _resolution,
                        decoration: const InputDecoration(
                          labelText: 'Resolution',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 5,
                            child: Text('QVGA 320 × 240'),
                          ),
                          DropdownMenuItem(
                            value: 8,
                            child: Text('VGA 640 × 480'),
                          ),
                          DropdownMenuItem(
                            value: 9,
                            child: Text('SVGA 800 × 600'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          _work(() async {
                            await _open();
                            if (!_demo) await _camera!.control('framesize', v);
                            if (mounted) {
                              setState(() {
                                _resolution = v;
                                if (_demo) _renderDemo();
                              });
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.flash_on_outlined),
                      const SizedBox(width: 8),
                      const Text('Flash'),
                      Switch(
                        key: const Key('camera-flash'),
                        value: _flash,
                        onChanged: (v) => _work(() => _setFlash(v)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SoftButton(
                    label: 'Analyze gallery image',
                    icon: Icons.photo_library_outlined,
                    busy: _busy,
                    onPressed: () => _work(() async {
                      final file = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 1920,
                        maxHeight: 1920,
                        imageQuality: 90,
                      );
                      if (file == null) {
                        if (mounted) {
                          setState(
                            () => _message = 'Image selection canceled.',
                          );
                        }
                        return;
                      }
                      if (await file.length() > 10 * 1024 * 1024) {
                        throw const FormatException('Image exceeds 10 MiB.');
                      }
                      await _analyze(await file.readAsBytes());
                    }),
                  ),
                  if (_demo)
                    SoftButton(
                      label: 'Use demo sample',
                      icon: Icons.science_outlined,
                      busy: _busy,
                      onPressed: () => _work(_capture),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (!_demo) ...[
          const SizedBox(height: 28),
          SoftPanel(
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Hardware connection'),
              subtitle: const Text(
                'Trusted local Wi-Fi · stream port 80, controls port 81',
              ),
              children: [
                SoftField(
                  child: TextField(
                    controller: _stream,
                    decoration: const InputDecoration(
                      labelText: 'Stream base URL',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SoftField(
                  child: TextField(
                    controller: _control,
                    decoration: const InputDecoration(
                      labelText: 'Control base URL',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SoftField(
                  child: TextField(
                    controller: _token,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Camera password',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(_message!, key: const Key('camera-message')),
          ),
        SoftPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Inspection result',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Center the gills inside the 200 × 200 pixel guide. HSV labels are experimental and require controlled lighting and validation.',
              ),
              if (_snapshot != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: SizedBox(
                    height: 200,
                    child: Image.memory(_snapshot!, fit: BoxFit.contain),
                  ),
                ),
              if (_analysis case final a?) ...[
                Text(
                  '${_demo ? 'SIMULATED TARGET' : 'Experimental result'}: ${a.classification}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'H ${a.hue.toStringAsFixed(1)}° · S ${(a.saturation * 100).toStringAsFixed(1)}% · V ${(a.value * 100).toStringAsFixed(1)}%',
                ),
                Text(
                  'Usable ROI ${(a.usableFraction * 100).toStringAsFixed(1)}% · red ${(a.redFraction * 100).toStringAsFixed(1)}%',
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Capture or import an image to begin.'),
                ),
              const SizedBox(height: 20),
              SoftField(
                child: TextField(
                  controller: _sample,
                  decoration: const InputDecoration(
                    labelText: 'Sample ID for inspection record',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SoftButton(
                label: _saved
                    ? 'Saved inspection'
                    : 'Save inspection image & result',
                icon: Icons.save_outlined,
                primary: true,
                busy: _busy,
                onPressed: () => _work(_save),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
