import 'package:flutter/material.dart';

class AppPreferences extends ChangeNotifier {
  bool highContrast = false;
  void setContrast(bool value) {
    highContrast = value;
    notifyListeners();
  }
}

class PreferencesScope extends InheritedNotifier<AppPreferences> {
  const PreferencesScope({
    super.key,
    required AppPreferences preferences,
    required super.child,
  }) : super(notifier: preferences);
  static AppPreferences? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreferencesScope>()?.notifier;
}
