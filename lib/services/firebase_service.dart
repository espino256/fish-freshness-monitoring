import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/fish_sample.dart';

abstract final class FirebaseService {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _databaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');
  static const _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  static bool get isConfigured =>
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _senderId.isNotEmpty &&
      _projectId.isNotEmpty &&
      _databaseUrl.isNotEmpty &&
      _storageBucket.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: _apiKey,
        appId: _appId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        databaseURL: _databaseUrl,
        storageBucket: _storageBucket,
      );

  static bool get isReady => Firebase.apps.isNotEmpty;

  static Stream<User?> get authChanges {
    if (!isReady) return Stream.value(null);
    return FirebaseAuth.instance.authStateChanges();
  }

  static User? get currentUser =>
      isReady ? FirebaseAuth.instance.currentUser : null;

  static Future<void> signIn(String email, String password) async {
    _requireReady();
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> sendPasswordReset(String email) async {
    _requireReady();
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  static Future<void> signOut() async {
    _requireReady();
    await FirebaseAuth.instance.signOut();
  }

  /// Bagong idinagdag para sa live ESP32 pH at Freshness telemetry
  static Stream<DatabaseEvent> watchFishFreshness() {
    _requireReady();
    return FirebaseDatabase.instance
        .ref('FishSamples/current_reading')
        .onValue;
  }

  static Stream<List<SensorReading>> watchReadings() {
    _requireReady();
    return FirebaseDatabase.instance
        .ref('readings')
        .limitToLast(100)
        .onValue
        .map((event) {
      final value = event.snapshot.value;
      if (value == null) return <SensorReading>[];
      if (value is! Map) {
        throw const FormatException('Firebase readings must be an object.');
      }
      final readings = value.entries
          .map(
            (entry) => SensorReading.fromFirebase(
              entry.key.toString(),
              entry.value,
            ),
          )
          .toList();
      readings.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return readings;
    });
  }

  static Stream<List<FishSample>> watchSamples() {
    _requireSignedIn();
    return FirebaseDatabase.instance.ref('samples').onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null) return <FishSample>[];
      if (value is! Map) {
        throw const FormatException('Firebase samples must be an object.');
      }
      final samples = value.entries.map((entry) {
        if (entry.value is! Map) {
          throw const FormatException(
            'Firebase sample metadata must be an object.',
          );
        }
        return FishSample.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }).toList();
      samples.sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
      return samples;
    });
  }

  static Stream<List<VisualAnalysisRecord>> watchAnalyses() {
    _requireReady();
    return FirebaseDatabase.instance.ref('analyses').onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null) return <VisualAnalysisRecord>[];
      if (value is! Map) {
        throw const FormatException('Firebase analyses must be an object.');
      }
      final records = value.entries
          .map(
            (entry) => VisualAnalysisRecord.fromFirebase(
              entry.key.toString(),
              entry.value,
            ),
          )
          .toList();
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return records;
    });
  }

  static Stream<List<DeviceStatus>> watchDevices() {
    _requireReady();
    return FirebaseDatabase.instance.ref('devices').onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null) return <DeviceStatus>[];
      if (value is! Map) {
        throw const FormatException('Firebase devices must be an object.');
      }
      return value.entries
          .map(
            (entry) =>
                DeviceStatus.fromFirebase(entry.key.toString(), entry.value),
          )
          .toList();
    });
  }

  static Stream<List<DeviceImageUpload>> watchDeviceUploads() {
    _requireSignedIn();
    return FirebaseDatabase.instance
        .ref('deviceUploads')
        .limitToLast(20)
        .onValue
        .map((event) {
      final value = event.snapshot.value;
      if (value == null) return <DeviceImageUpload>[];
      if (value is! Map) {
        throw const FormatException(
          'Firebase device uploads must be an object.',
        );
      }
      final uploads = value.entries
          .map(
            (entry) => DeviceImageUpload.fromFirebase(
              entry.key.toString(),
              entry.value,
            ),
          )
          .toList();
      uploads.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return uploads;
    });
  }

  static Future<void> saveSample(FishSample sample) async {
    _requireSignedIn();
    final userId = currentUser!.uid;
    final id = sample.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    await FirebaseDatabase.instance.ref('samples/$id').set({
      ...sample.toJson(),
      'ownerUid': userId,
      'updatedBy': userId,
      'updatedAt': ServerValue.timestamp,
    });
  }

  static Future<void> deleteSample(String sampleId) async {
    _requireSignedIn();
    final id = sampleId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    await FirebaseDatabase.instance.ref('samples/$id').remove();
  }

  static Future<String> uploadAnalysis({
    required String sampleId,
    required Uint8List imageBytes,
    required String fileName,
    required double meanHue,
    required String classification,
  }) async {
    _requireSignedIn();
    final user = currentUser!;
    final safeSampleId = sampleId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeFileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        'samples/$safeSampleId/images/'
        '${DateTime.now().millisecondsSinceEpoch}_$safeFileName';
    final reference = FirebaseStorage.instance.ref(path);
    await reference.putData(
      imageBytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    try {
      await _saveAnalysisMetadata(
        sampleId: sampleId,
        storagePath: path,
        meanHue: meanHue,
        classification: classification,
        userId: user.uid,
      );
    } on Object catch (error) {
      try {
        await reference.delete();
      } on FirebaseException catch (cleanupError) {
        throw StateError(
          'Analysis metadata could not be saved ($error) and the uploaded '
          'image could not be removed (${cleanupError.message}).',
        );
      }
      rethrow;
    }
    return path;
  }

  static Future<void> saveAnalysisReference({
    required String sampleId,
    required String storagePath,
    required double meanHue,
    required String classification,
  }) async {
    _requireSignedIn();
    final safeSampleId = sampleId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    if (!storagePath.startsWith('samples/$safeSampleId/images/')) {
      throw ArgumentError.value(
        storagePath,
        'storagePath',
        'Must reference an image stored for the selected sample.',
      );
    }
    await _saveAnalysisMetadata(
      sampleId: sampleId,
      storagePath: storagePath,
      meanHue: meanHue,
      classification: classification,
      userId: currentUser!.uid,
    );
  }

  static Future<void> _saveAnalysisMetadata({
    required String sampleId,
    required String storagePath,
    required double meanHue,
    required String classification,
    required String userId,
  }) async {
    await FirebaseDatabase.instance.ref('analyses').push().set({
      'sampleId': sampleId,
      'storagePath': storagePath,
      'meanHue': meanHue,
      'classification': classification,
      'timestamp': ServerValue.timestamp,
      'createdBy': userId,
    });
  }

  static Future<Uint8List?> downloadImage(String storagePath) async {
    _requireSignedIn();
    return FirebaseStorage.instance.ref(storagePath).getData(10 * 1024 * 1024);
  }

  static void _requireReady() {
    if (!isReady) {
      throw StateError(
        'Firebase is not configured. Follow the README setup instructions.',
      );
    }
  }

  static void _requireSignedIn() {
    _requireReady();
    if (currentUser == null) {
      throw StateError('Sign in before syncing Firebase data.');
    }
  }
}