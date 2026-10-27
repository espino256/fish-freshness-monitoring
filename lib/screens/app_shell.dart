import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/classification.dart';
import '../models/fish_sample.dart';
import '../services/firebase_service.dart';
import '../services/local_store.dart';
import '../widgets/aqua_brand_mark.dart';
import 'pages.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.firebaseStartupError});

  final String? firebaseStartupError;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _titles = [
    'Dashboard',
    'Live monitoring',
    'Visual analysis',
    'Samples',
    'History',
    'Reports',
    'Calibration',
    'Settings',
  ];

  final _store = LocalStore();
  final _samplesPageKey = GlobalKey<SamplesPageState>();
  List<FishSample> _samples = [];
  List<Map<String, Object?>> _calibrations = [];
  FreshnessThresholds _thresholds = const FreshnessThresholds();
  int _selectedIndex = 0;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _persistenceError;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<FishSample>>? _cloudSamplesSubscription;
  String? _cloudUserId;
  List<FishSample>? _pendingCloudSamples;
  final Set<String> _cloudSampleIds = {};

  @override
  void initState() {
    super.initState();
    _load();
    if (FirebaseService.isReady) {
      _authSubscription = FirebaseService.authChanges.listen(
        _listenForCloudSamples,
        onError: (Object error) {
          if (mounted) {
            setState(
              () => _persistenceError = 'Firebase auth stream failed: $error',
            );
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _cloudSamplesSubscription?.cancel();
    super.dispose();
  }

  void _listenForCloudSamples(User? user) {
    if (_cloudUserId == user?.uid) return;
    _cloudUserId = user?.uid;
    _cloudSampleIds.clear();
    _cloudSamplesSubscription?.cancel();
    if (user == null) return;
    _cloudSamplesSubscription = FirebaseService.watchSamples().listen(
      (cloudSamples) {
        if (_loading) {
          _pendingCloudSamples = cloudSamples;
        } else {
          _mergeCloudSamples(cloudSamples);
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(
            () => _persistenceError = 'Could not sync cloud samples: $error',
          );
        }
      },
    );
  }

  void _mergeCloudSamples(List<FishSample> cloudSamples) {
    _cloudSampleIds
      ..clear()
      ..addAll(cloudSamples.map((sample) => sample.id));
    final merged = <String, FishSample>{
      for (final sample in cloudSamples) sample.id: sample,
      for (final sample in _samples) sample.id: sample,
    }.values.toList()..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
    if (!mounted) return;
    setState(() {
      _samples = merged;
      _pendingCloudSamples = null;
      _persistenceError = null;
    });
    _store.saveSamples(merged).catchError((Object error) {
      if (mounted) {
        setState(() {
          _persistenceError =
              'Cloud samples loaded, but local persistence failed: $error';
        });
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait<Object>([
        _store.loadSamples(),
        _store.loadThresholds(),
        _store.loadCalibrations(),
      ]);
      if (!mounted) return;
      setState(() {
        _samples = results[0] as List<FishSample>;
        _thresholds = results[1] as FreshnessThresholds;
        _calibrations = results[2] as List<Map<String, Object?>>;
        _loading = false;
      });
      final pending = _pendingCloudSamples;
      if (pending != null) _mergeCloudSamples(pending);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load saved workspace data: $error';
        _loading = false;
      });
    }
  }

  Future<void> _saveSamples(List<FishSample> samples) async {
    final previous = _samples;
    setState(() {
      _saving = true;
      _persistenceError = null;
    });
    try {
      await _store.saveSamples(samples);
      if (!mounted) return;
      setState(() {
        _samples = samples;
        _saving = false;
      });
      if (FirebaseService.isReady && FirebaseService.currentUser != null) {
        try {
          final currentIds = samples.map((sample) => sample.id).toSet();
          final previousById = {
            for (final sample in previous) sample.id: sample,
          };
          for (final sample in samples) {
            final old = previousById[sample.id];
            if (old == null || !_sameSample(old, sample)) {
              await FirebaseService.saveSample(sample);
              _cloudSampleIds.add(sample.id);
            }
          }
          for (final removed in previous.where(
            (sample) =>
                !currentIds.contains(sample.id) &&
                _cloudSampleIds.contains(sample.id),
          )) {
            await FirebaseService.deleteSample(removed.id);
            _cloudSampleIds.remove(removed.id);
          }
        } on Object catch (error) {
          if (!mounted) return;
          setState(() {
            _persistenceError =
                'Changes were saved locally, but Firebase sync failed: $error';
          });
        }
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _persistenceError = 'Could not save sample changes: $error';
        _saving = false;
      });
      rethrow;
    }
  }

  bool _sameSample(FishSample first, FishSample second) =>
      first.id == second.id &&
      first.fishType == second.fishType &&
      first.details == second.details &&
      first.collectedAt == second.collectedAt &&
      first.operatorName == second.operatorName &&
      first.remarks == second.remarks;

  Future<void> _saveThresholds(FreshnessThresholds thresholds) async {
    await _store.saveThresholds(thresholds);
    if (!mounted) return;
    setState(() => _thresholds = thresholds);
  }

  Future<void> _saveCalibration(Map<String, Object?> record) async {
    await _store.saveCalibration(record);
    if (!mounted) return;
    setState(() => _calibrations = [record, ..._calibrations]);
  }

  void _navigate(int index) => setState(() => _selectedIndex = index);

  Future<void> _showMoreMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 2; i < _titles.length; i++)
              ListTile(
                leading: Icon(_icons[i]),
                title: Text(_titles[i]),
                onTap: () {
                  Navigator.pop(context);
                  _navigate(i);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseService.authChanges,
      builder: (context, authSnapshot) {
        final user = authSnapshot.data;
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            return Scaffold(
              appBar: AppBar(
                backgroundColor: AppColors.surface,
                titleSpacing: wide ? 10 : 18,
                title: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _titles[_selectedIndex],
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (!wide)
                            const Text(
                              'AQUASENSE · RESEARCH WORKSPACE',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 9,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  if (FirebaseService.isConfigured && user != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: PopupMenuButton<String>(
                        tooltip: 'Account options',
                        onSelected: (value) async {
                          if (value != 'signOut') return;
                          try {
                            await FirebaseService.signOut();
                          } on FirebaseAuthException catch (error) {
                            _showMessage(
                              error.message ?? 'Could not sign out.',
                            );
                          } on Exception catch (error) {
                            _showMessage('Could not sign out: $error');
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            enabled: false,
                            child: Text(
                              user.email ?? 'Signed-in researcher',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'signOut',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.logout_rounded),
                              title: Text('Sign out'),
                            ),
                          ),
                        ],
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.aqua.withValues(
                            alpha: 0.24,
                          ),
                          child: Text(
                            (user.email?.trim().isNotEmpty ?? false)
                                ? user.email!.trim()[0].toUpperCase()
                                : 'A',
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (FirebaseService.isConfigured)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: TextButton.icon(
                        onPressed: _showSignIn,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Sign in'),
                      ),
                    ),
                ],
              ),
              body: SafeArea(
                top: false,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        children: [
                          if (wide) _sideNavigation(),
                          Expanded(
                            child: Column(
                              children: [
                                if (widget.firebaseStartupError != null)
                                  _banner(
                                    'Firebase startup error: '
                                    '${widget.firebaseStartupError}',
                                    AppColors.spoiled,
                                  ),
                                if (!FirebaseService.isReady)
                                  _banner(
                                    FirebaseService.isConfigured
                                        ? 'Firebase configuration was supplied, '
                                              'but the connection did not start.'
                                        : 'Local workspace mode · Firebase is '
                                              'not configured · Sensor readings '
                                              'are not available',
                                    AppColors.moderate,
                                  ),
                                if (_loadError != null)
                                  _banner(_loadError!, AppColors.spoiled),
                                if (_persistenceError != null)
                                  _banner(
                                    _persistenceError!,
                                    AppColors.spoiled,
                                  ),
                                Expanded(
                                  child: _loading
                                      ? const SizedBox.shrink()
                                      : _loadError != null
                                      ? Center(
                                          child: FilledButton.icon(
                                            onPressed: _load,
                                            icon: const Icon(Icons.refresh),
                                            label: const Text('Retry loading'),
                                          ),
                                        )
                                      : _screen(user),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              bottomNavigationBar: wide
                  ? null
                  : NavigationBar(
                      selectedIndex: _mobileSelectedIndex,
                      onDestinationSelected: (index) {
                        switch (index) {
                          case 0:
                            _navigate(0);
                          case 1:
                            _navigate(1);
                          case 2:
                            _navigate(3);
                          case 3:
                            _showMoreMenu();
                        }
                      },
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.space_dashboard_outlined),
                          selectedIcon: Icon(Icons.space_dashboard_rounded),
                          label: 'Home',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.sensors_outlined),
                          selectedIcon: Icon(Icons.sensors_rounded),
                          label: 'Live',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.science_outlined),
                          selectedIcon: Icon(Icons.science_rounded),
                          label: 'Samples',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.menu_rounded),
                          label: 'More',
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  int get _mobileSelectedIndex {
    if (_selectedIndex == 0) return 0;
    if (_selectedIndex == 1) return 1;
    if (_selectedIndex == 3) return 2;
    return 3;
  }

  Widget _sideNavigation() => Container(
    width: 248,
    padding: const EdgeInsets.fromLTRB(14, 14, 12, 18),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.navyDeep, AppColors.navy],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    ),
    child: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 7, 10, 22),
          child: Row(
            children: [
              AquaBrandMark(size: 42),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AquaSense',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'AQUA INTELLIGENCE',
                      style: TextStyle(
                        color: AppColors.aqua,
                        fontSize: 9,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 8, 9),
          child: Text(
            'WORKSPACE',
            style: TextStyle(
              color: Color(0xFF8FAAB2),
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (var i = 0; i < _titles.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Material(
              color: _selectedIndex == i
                  ? AppColors.aqua.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _navigate(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      if (_selectedIndex == i)
                        Container(
                          width: 3,
                          height: 24,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: AppColors.aqua,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )
                      else
                        const SizedBox(width: 13),
                      Icon(
                        _icons[i],
                        color: _selectedIndex == i
                            ? AppColors.aqua
                            : const Color(0xFF9EB5BB),
                        size: 20,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          _titles[i],
                          style: TextStyle(
                            color: _selectedIndex == i
                                ? Colors.white
                                : const Color(0xFFC1D0D4),
                            fontWeight: _selectedIndex == i
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.aqua, size: 17),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Research tool only. Neither pH nor color alone determines '
                  'food safety.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFFC1D0D4),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static const _icons = [
    Icons.space_dashboard_rounded,
    Icons.sensors_rounded,
    Icons.image_search_rounded,
    Icons.science_rounded,
    Icons.history_rounded,
    Icons.description_outlined,
    Icons.tune_rounded,
    Icons.settings_outlined,
  ];

  Widget _screen(User? user) {
    final page = switch (_selectedIndex) {
      0 => DashboardPage(
        samples: _samples,
        thresholds: _thresholds,
        onNavigate: _navigate,
        onAddSample: _addSample,
      ),
      1 => LiveMonitoringPage(thresholds: _thresholds),
      2 => VisualAnalysisPage(
        samples: _samples,
        user: user,
        thresholds: _thresholds,
      ),
      3 => SamplesPage(
        key: _samplesPageKey,
        samples: _samples,
        thresholds: _thresholds,
        onSave: _saveSamples,
        onError: _showMessage,
      ),
      4 => HistoryPage(samples: _samples, thresholds: _thresholds),
      5 => ReportsPage(samples: _samples, calibrations: _calibrations),
      6 => CalibrationPage(records: _calibrations, onSave: _saveCalibration),
      _ => SettingsPage(
        thresholds: _thresholds,
        onSave: _saveThresholds,
        user: user,
        onSignIn: _showSignIn,
        startupError: widget.firebaseStartupError,
      ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: KeyedSubtree(key: ValueKey(_selectedIndex), child: page),
    );
  }

  void _addSample() {
    _navigate(3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _samplesPageKey.currentState?.openCreateForm();
    });
  }

  Future<void> _showSignIn() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _SignInDialog(),
    );
    if (result != null && mounted) _showMessage(result);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _banner(String message, Color color) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog();

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseService.signIn(_email.text.trim(), _password.text);
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (error) {
      setState(() {
        _error = error.message ?? 'Sign-in failed. Check your credentials.';
        _loading = false;
      });
    } on StateError catch (error) {
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address first.');
      return;
    }
    try {
      await FirebaseService.sendPasswordReset(email);
      if (mounted) {
        setState(() {
          _error = 'Password reset email sent.';
          _loading = false;
        });
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _error = error.message ?? 'Could not send reset email.');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sign in to AquaSense'),
    content: SizedBox(
      width: 380,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) => value == null || !value.contains('@')
                  ? 'Enter a valid email.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your password.'
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.spoiled),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _loading ? null : _resetPassword,
        child: const Text('Forgot password?'),
      ),
      TextButton(
        onPressed: _loading ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _loading ? null : _submit,
        child: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Sign in'),
      ),
    ],
  );
}
