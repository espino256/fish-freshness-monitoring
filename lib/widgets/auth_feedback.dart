import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

String authMessage(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-credential' ||
      'user-not-found' ||
      'wrong-password' => 'Email or password is incorrect.',
      'email-already-in-use' =>
        'This email already has an account. Sign in or reset your password.',
      'weak-password' =>
        'Choose a stronger password with at least 8 characters.',
      'invalid-email' => 'Enter a valid email address.',
      'user-disabled' =>
        'This account is disabled. Contact your project administrator.',
      'too-many-requests' => 'Too many attempts. Please try again later.',
      'network-request-failed' =>
        'Connection failed. Check your network and try again.',
      'popup-closed-by-user' || 'cancelled-popup-request' =>
        'Google sign-in was canceled. You can try again.',
      'popup-blocked' =>
        'Allow the Google sign-in popup in your browser, then retry.',
      'operation-not-allowed' =>
        'Enable this sign-in provider in your Firebase project.',
      'invalid-api-key' =>
        'The Firebase API key is invalid. Check your local build configuration.',
      _ => error.message ?? 'Authentication failed. Please retry.',
    };
  }
  if (error is StateError) return error.message.toString();
  if (error is TimeoutException) {
    return 'Firebase did not respond in time. Check your connection and retry.';
  }
  if (error is UnsupportedError) {
    return error.message ?? 'Use email sign-in on this platform.';
  }
  return 'Unable to complete authentication. Check provider configuration and connectivity, then retry.';
}

void showAuthFeedback(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.fixed,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Dismiss',
        onPressed: () => messenger.hideCurrentSnackBar(),
      ),
    ),
  );
}
