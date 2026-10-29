import 'package:flutter/material.dart';
import '../core/app_preferences.dart';
import '../services/firebase_service.dart';
import '../widgets/soft_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.onRefresh,
    required this.onRetryCloud,
    required this.role,
  });
  final VoidCallback onRefresh, onRetryCloud;
  final String role;
  @override
  Widget build(BuildContext context) {
    final preferences = PreferencesScope.maybeOf(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Workspace settings',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Manage your live Firebase connection and display preferences.',
        ),
        const SizedBox(height: 28),
        SoftPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Connection', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('Firebase · $role'),
              const SizedBox(height: 12),
              Text(
                FirebaseService.currentUser?.email ??
                    'Sign in with your Firebase account.',
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SoftButton(
                    label: 'Refresh workspace',
                    icon: Icons.refresh,
                    onPressed: onRefresh,
                  ),
                  SoftButton(
                    label: 'Retry cloud connection',
                    icon: Icons.cloud_sync_outlined,
                    onPressed: onRetryCloud,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SoftPanel(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('High contrast'),
            subtitle: const Text('Strengthen text and field outlines.'),
            value: preferences?.highContrast ?? false,
            onChanged: (v) {
              if (preferences != null) {
                preferences.setContrast(v);
              } else {
                showNotice(
                  context,
                  'Open settings from the AquaSense workspace to change display preferences.',
                );
              }
            },
          ),
        ),
        const SizedBox(height: 28),
        const SoftPanel(
          child: Text(
            'Sign-up, email sign-in, Google sign-in and password reset use Firebase Authentication. No local identity can open the workspace. Cloud inspection history is immutable.',
          ),
        ),
        const SizedBox(height: 24),
        SoftButton(
          label: 'About AquaSense',
          icon: Icons.info_outline,
          onPressed: () => showAboutDialog(
            context: context,
            applicationName: 'AquaSense',
            applicationVersion: '1.0.0',
            children: [
              const Text(
                'Mobile-Based Fish Freshness Monitoring System. pH and experimental HSV results require calibration and do not certify food safety. The water backdrop is an AI-generated design asset.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
