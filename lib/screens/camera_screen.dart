import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/app_theme.dart';
import '../services/camera_service.dart';
import '../services/demo_session.dart';
import '../services/visual_inspection_service.dart';
import '../services/ai_inference_service.dart';
import '../models/experimental_ai.dart';
import '../models/visual_inspection.dart';
import '../models/image_region.dart';
import '../models/telemetry.dart';
import '../widgets/soft_ui.dart';
import '../widgets/inspection_card.dart';
import '../widgets/experimental_inspection_details.dart';
import '../widgets/fish_region_selector.dart';
import '../widgets/live_ph_card.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.canSave,
    this.onSaveInspection,
    this.inferenceService,
    this.phReadings,
    this.telemetryUnavailableReason,
    this.onRefreshTelemetry,
  });
  final bool canSave;
  final Future<void> Function(
    VisualInspectionResult inspection,
    ExperimentalFishModel model,
  )?
  onSaveInspection;
  final AiInferenceService? inferenceService;
  final Stream<List<Telemetry>>? phReadings;
  final String? telemetryUnavailableReason;
  final VoidCallback? onRefreshTelemetry;
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final _stream = TextEditingController(text: 'http://esp32cam.local'),
      _control = TextEditingController(text: 'http://esp32cam.local:81'),
      _token = TextEditingController();
  CameraService? _camera;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _demoTimer, _flashTimer;
  Uint8List? _frame, _sourceBytes;
  InspectionImagePreview? _preview;
  ImageRegion? _region;
  int _quarterTurns = 0, _imageRevision = 0;
  VisualInspectionResult? _inspection;
  late final AiInferenceService _inference;
  int _analysisRevision = 0;
  ExperimentalFishModel _scalesModel = ExperimentalFishModel.scales;
  ExperimentalFishModel get _model => _selectedPart == FishPart.skinScales
      ? _scalesModel
      : ExperimentalFishModel.forPart(_selectedPart);
  FishPart _selectedPart = FishPart.gills;
  String? _message;
  bool _busy = false, _flash = false, _demoConnected = false;
  bool _savingInspection = false, _inspectionSaved = false;
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
    _inference = widget.inferenceService ?? AiInferenceService();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = DemoScope.maybeOf(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _disconnect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _analysisRevision++;
    unawaited(_inference.dispose());
    _subscription?.cancel();
    _camera?.close();
    _demoTimer?.cancel();
    _flashTimer?.cancel();
    for (final c in [_stream, _control, _token]) {
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

  Future<void> _analyze(Uint8List bytes, {bool newImage = true}) async {
    final part = _selectedPart;
    final model = _model;
    final revision = ++_analysisRevision;
    if (mounted) {
      setState(() {
        _inspectionSaved = false;
        if (newImage) {
          _sourceBytes = bytes;
          _region = null;
          _quarterTurns = 0;
          _preview = null;
          _imageRevision++;
        }
        _inspection = VisualInspectionResult(
          part: part,
          width: 0,
          height: 0,
          isImageUsable: false,
          reason: 'Checking image and running experimental inference.',
          experimentalAi: ExperimentalAiResult(
            model: model,
            status: ExperimentalAiStatus.running,
            message: 'Checking image, loading model and running inference.',
          ),
        );
      });
    }
    VisualInspectionResult result;
    try {
      final request = VisualInspectionRequest(
        bytes,
        part,
        region: _region,
        quarterTurns: _quarterTurns,
      );
      if (_preview == null) {
        final preview = await compute(VisualInspectionService.preview, request);
        if (!mounted || revision != _analysisRevision) return;
        setState(() => _preview = preview);
      }
      result = await _inference.analyze(request, model: model);
    } on Object {
      result = VisualInspectionResult(
        part: part,
        width: 0,
        height: 0,
        isImageUsable: false,
        reason:
            'Image inspection failed. Choose another image or try again. Freshness is inconclusive.',
      );
    }
    if (!mounted || revision != _analysisRevision) return;
    setState(() {
      _inspection = result;
    });
  }

  Future<void> _capture() async {
    _clearInspection();
    await _open();
    if (!mounted) return;
    final bytes = _demo ? _frame! : await _camera!.capture();
    await _analyze(bytes);
  }

  void _inspectionFailed(FishPart part, String reason) {
    if (!mounted) return;
    setState(() {
      _analysisRevision++;
      _sourceBytes = null;
      _preview = null;
      _region = null;
      _imageRevision++;
      _inspectionSaved = false;
      _inspection = VisualInspectionResult(
        part: part,
        width: 0,
        height: 0,
        isImageUsable: false,
        reason: reason,
        experimentalAi: ExperimentalAiResult(
          model: _model,
          status: ExperimentalAiStatus.qualityRejected,
          message: reason,
        ),
      );
    });
  }

  Future<void> _importGallery() async {
    final part = _selectedPart;
    _clearInspection();
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );
      if (!mounted) return;
      if (file == null) {
        setState(() => _message = 'Image selection canceled.');
        return;
      }
      if (await file.length() > 10 * 1024 * 1024) {
        _inspectionFailed(
          part,
          'Image exceeds 10 MiB. Choose a smaller JPEG or PNG.',
        );
        return;
      }
      await _analyze(await file.readAsBytes());
    } on Object {
      _inspectionFailed(
        part,
        'The selected image could not be read. Choose another image. Freshness is inconclusive.',
      );
    }
  }

  void _clearInspection() {
    if (!mounted) return;
    setState(() {
      _analysisRevision++;
      _sourceBytes = null;
      _preview = null;
      _region = null;
      _quarterTurns = 0;
      _imageRevision++;
      _inspection = null;
      _message = null;
    });
  }

  void _regionChanged() {
    if (!mounted) return;
    setState(() {
      _analysisRevision++;
      _region = null;
      _inspection = null;
      _inspectionSaved = false;
      _message = null;
    });
  }

  void _selectionChanged() {
    _regionChanged();
    setState(() => _imageRevision++);
  }

  Future<void> _applyRegion(ImageRegion region) async {
    final bytes = _sourceBytes;
    if (bytes == null) return;
    _region = region;
    await _analyze(bytes, newImage: false);
  }

  Future<void> _saveInspection(VisualInspectionResult inspection) async {
    final save = widget.onSaveInspection;
    if (!widget.canSave || save == null || _savingInspection) return;
    setState(() {
      _savingInspection = true;
      _message = null;
    });
    try {
      await save(inspection, _model);
      if (!mounted) return;
      setState(() {
        _inspectionSaved = true;
        _message = 'Inspection saved to history.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Could not save inspection: $error');
    } finally {
      if (mounted) setState(() => _savingInspection = false);
    }
  }

  Future<void> _rotateImage() async {
    final bytes = _sourceBytes;
    if (bytes == null) return;
    _selectionChanged();
    _quarterTurns = (_quarterTurns + 1) % 4;
    _preview = null;
    await _analyze(bytes, newImage: false);
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
    final preview = _preview;
    return Stack(
      children: [
        ResponsivePageList(
          children: [
            Text(
              'Camera & AI Inspection',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _demo
                  ? 'DEMO · Synthetic target and simulated camera controls.'
                  : 'Choose a fish part and image. Explore experimental scores and image descriptors.',
            ),
            const SizedBox(height: 20),
            LivePhCard(
              readings: widget.phReadings ?? (_demo ? _session!.live : null),
              unavailableReason: widget.telemetryUnavailableReason,
              onRefresh: widget.onRefreshTelemetry,
              simulated: _demo,
            ),
            const SizedBox(height: 20),
            SoftPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: DropdownButtonFormField<FishPart>(
                      key: const Key('fish-part-selector'),
                      initialValue: _selectedPart,
                      decoration: const InputDecoration(
                        labelText: 'Visible fish part',
                      ),
                      items: FishPart.values
                          .map(
                            (part) => DropdownMenuItem(
                              value: part,
                              child: Text(part.label),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (part) {
                              if (part != null) {
                                setState(() {
                                  _selectedPart = part;
                                  _scalesModel = ExperimentalFishModel.scales;
                                });
                                _selectionChanged();
                              }
                            },
                    ),
                  ),
                  if (_selectedPart == FishPart.skinScales) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<ExperimentalFishModel>(
                      key: const Key('scales-model-selector'),
                      initialValue: _scalesModel,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Scales experiment',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ExperimentalFishModel.scales,
                          child: Text('Original Scales model'),
                        ),
                        DropdownMenuItem(
                          value: ExperimentalFishModel.scalesFinetuned,
                          child: Text('Fine-tuned candidate'),
                        ),
                      ],
                      onChanged: _busy
                          ? null
                          : (model) {
                              if (model == null) return;
                              _selectionChanged();
                              setState(() => _scalesModel = model);
                            },
                    ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      SoftButton(
                        label: 'Analyze gallery image',
                        icon: Icons.photo_library_outlined,
                        busy: _busy,
                        onPressed: () => _work(_importGallery),
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
            const SizedBox(height: 20),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_message!, key: const Key('camera-message')),
              ),
            if (preview?.bytes != null)
              FishRegionSelector(
                key: ValueKey('photo-$_imageRevision'),
                bytes: preview!.bytes!,
                width: preview.width,
                height: preview.height,
                part: _selectedPart,
                busy: _busy,
                onChanged: _regionChanged,
                onApply: (region) => _work(() => _applyRegion(region)),
                onRotate: () => _work(_rotateImage),
                onChangeImage: () => _work(_importGallery),
              )
            else
              SoftPanel(
                child: Column(
                  children: [
                    const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 48,
                      color: AppColors.teal,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      preview?.reason ?? 'Capture or import an image to begin.',
                    ),
                    const Text(
                      'Image proportions and orientation will be preserved. Select a region to calculate descriptors.',
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            if (_inspection case final result?) ...[
              ExperimentalInspectionDetails(result: result, simulated: _demo),
              if (widget.canSave && widget.onSaveInspection != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SoftButton(
                      label: _inspectionSaved
                          ? 'Saved to history'
                          : 'Save inspection to history',
                      icon: _inspectionSaved
                          ? Icons.check_circle_outline
                          : Icons.save_outlined,
                      primary: !_inspectionSaved,
                      busy: _savingInspection,
                      onPressed: () => _saveInspection(result),
                    ),
                  ),
                ),
            ] else if (_sourceBytes != null)
              const SoftPanel(
                child: Text(
                  'Previous scores and descriptors cleared. Apply a fish-part region to analyze this image again.',
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'ESP32-CAM controls',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect your camera or capture a still image for inspection.',
            ),
            const SizedBox(height: 12),
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
                        width: 200,
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
                                if (!_demo) {
                                  await _camera!.control('framesize', v);
                                }
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
                ],
              ),
            ),
            if (!_demo) ...[
              const SizedBox(height: 28),
              SoftPanel(
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
                  title: const Text('Hardware connection'),
                  subtitle: const Text(
                    'Trusted local Wi-Fi · stream port 80, controls port 81',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SoftField(
                        child: TextField(
                          controller: _stream,
                          decoration: const InputDecoration(
                            labelText: 'Stream base URL',
                          ),
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
            const SizedBox(height: 20),
            const Text(
              'Saving a freshness classification is disabled until model labels and validation evidence are available.',
            ),
          ],
        ),
        if (_busy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              key: Key('inspection-busy'),
              semanticsLabel: 'Inspection operation in progress',
            ),
          ),
      ],
    );
  }
}
