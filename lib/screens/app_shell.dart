import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/firebase_service.dart';
import '../services/monitoring_repository.dart';
import '../services/demo_session.dart';
import '../models/telemetry.dart';
import '../models/fish_sample.dart';
import '../models/visual_inspection_history.dart';
import '../widgets/soft_ui.dart';
import '../widgets/aqua_brand_mark.dart';
import '../widgets/account_setup_notice.dart';
import 'dashboard_screen.dart';
import 'camera_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.firebaseStartupError,
    this.onRetryCloud,
    this.userUid,
  });
  final String? userUid;
  final String? firebaseStartupError;
  final VoidCallback? onRetryCloud;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0, _revision = 0;
  String _role = 'Signed-in user';
  bool _inspector = false;
  DemoSession? _session;
  Stream<List<Telemetry>>? _live, _history;
  Stream<List<VisualAnalysisRecord>>? _analyses;
  Stream<List<VisualInspectionHistoryRecord>>? _visualInspections;
  static const labels = [
    'Dashboard',
    'Camera & AI Inspection',
    'History',
    'Settings',
  ];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.videocam_outlined,
    Icons.history,
    Icons.tune,
  ];
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = DemoScope.maybeOf(context);
    if (_live == null || _session != session) {
      _session = session;
      _connectStreams();
    }
  }

  void _connectStreams() {
    if (_session?.enabled == true) {
      _live = _session!.live;
      _history = _session!.history;
      _analyses = _session!.analyses;
      _visualInspections = _session!.inspectionHistory;
      _inspector = true;
    } else if (FirebaseService.isReady) {
      final repository = MonitoringRepository();
      _live = repository.watchLive();
      _history = repository.watchHistory();
      _analyses = FirebaseService.watchAnalyses();
      _visualInspections = FirebaseService.watchVisualInspections();
      _refreshRole();
    } else {
      _live = Stream.value([]);
      _history = Stream.value([]);
      _analyses = Stream.value([]);
      _visualInspections = Stream.value([]);
    }
  }

  Future<void> _refreshRole() async {
    try {
      final token = await FirebaseService.currentUser?.getIdTokenResult(true);
      final role = token?.claims?['role'];
      if (mounted) {
        setState(() {
          _role = role is String ? role : 'Signed-in user';
          _inspector = role == 'inspector' || role == 'admin';
        });
      }
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'Could not refresh permissions. Check your connection.',
        );
      }
    }
  }

  void _refresh() {
    if (_session?.enabled == true) {
      _session!.refresh();
    } else {
      setState(() {
        _connectStreams();
        _revision++;
      });
    }
    showNotice(
      context,
      _session?.enabled == true
          ? 'Demo telemetry refreshed.'
          : 'Cloud subscriptions refreshed.',
    );
  }

  Future<void> _signOut() async {
    try {
      await FirebaseService.signOut();
    } catch (_) {
      if (mounted) showNotice(context, 'Sign out failed. Please retry.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = _session?.enabled == true;
    final telemetryUnavailableReason = demo
        ? null
        : !FirebaseService.isReady
        ? 'Firebase is not connected. Reconnect cloud services in Settings.'
        : FirebaseService.currentUser == null
        ? 'Sign in to view sensor pH readings.'
        : !FirebaseService.currentUser!.emailVerified
        ? 'Verify your email using the Verify button above, then refresh the sensor feed.'
        : null;
    final content = switch (_tab) {
      0 => DashboardScreen(
        key: ValueKey('dashboard-$_revision'),
        readings: _live!,
        historyReadings: _history,
        onRefresh: _refresh,
        telemetryUnavailableReason: telemetryUnavailableReason,
      ),
      1 => CameraScreen(
        canSave: _inspector,
        onSaveInspection: (inspection, model) async {
          if (_session?.enabled == true) {
            _session!.saveVisualInspection(inspection, model);
          } else {
            await FirebaseService.saveVisualInspection(inspection, model);
          }
        },
        phReadings: _live,
        telemetryUnavailableReason: telemetryUnavailableReason,
        onRefreshTelemetry: _refresh,
      ),
      2 => HistoryScreen(
        key: ValueKey('history-$_revision'),
        readings: _history!,
        analyses: _analyses!,
        visualInspections: _visualInspections!,
      ),
      _ => SettingsScreen(
        onRefresh: _refresh,
        onRetryCloud:
            widget.onRetryCloud ??
            () => showNotice(
              context,
              'Configure Firebase and rebuild to connect cloud services.',
            ),
        role: _role,
      ),
    };
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            final short = constraints.maxHeight < 500;
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 36 : 16,
                    vertical: short ? 8 : 14,
                  ),
                  child: Row(
                    children: [
                      const AquaBrandMark(size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AquaSense',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (!short)
                              const Text(
                                'FISH FRESHNESS MONITORING',
                                style: TextStyle(
                                  color: Color(0xFFC5DDE2),
                                  fontSize: 9,
                                  letterSpacing: 1.1,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                      ),
                      IconButton(
                        tooltip: 'Sign out',
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      demo
                          ? 'COMPONENT TEST · SYNTHETIC SENSOR DATA'
                          : 'CLOUD WORKSPACE · FIREBASE ACCOUNT',
                      style: const TextStyle(
                        color: AppColors.mint,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AccountSetupNotice(onVerified: _refresh),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 28 : 12,
                      0,
                      wide ? 28 : 12,
                      12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide) ...[
                          SizedBox(
                            width: 256,
                            child: SoftPanel(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 22,
                              ),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text(
                                        'WORKSPACE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ),
                                    for (var i = 0; i < labels.length; i++)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 14,
                                        ),
                                        child: SoftButton(
                                          label: labels[i],
                                          icon: icons[i],
                                          primary: _tab == i,
                                          onPressed: () =>
                                              setState(() => _tab = i),
                                        ),
                                      ),
                                    const SizedBox(height: 20),
                                    Text(
                                      demo
                                          ? 'Sandbox session\nNo cloud writes'
                                          : 'Secure Firebase access',
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                        ],
                        Expanded(
                          child: SoftPanel(
                            padding: EdgeInsets.zero,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: content,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: SoftPanel(
                      padding: const EdgeInsets.all(4),
                      child: NavigationBar(
                        height: short
                            ? 64
                            : 76 + (textScale - 1).clamp(0, 2) * 40,
                        labelBehavior: short
                            ? NavigationDestinationLabelBehavior.alwaysHide
                            : NavigationDestinationLabelBehavior.alwaysShow,
                        selectedIndex: _tab,
                        onDestinationSelected: (v) => setState(() => _tab = v),
                        destinations: [
                          for (var i = 0; i < labels.length; i++)
                            NavigationDestination(
                              icon: Icon(icons[i]),
                              label: i == 1 && constraints.maxWidth < 600
                                  ? 'Inspect'
                                  : labels[i],
                              tooltip: labels[i],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
