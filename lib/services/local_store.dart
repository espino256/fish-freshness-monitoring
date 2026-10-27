import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/classification.dart';
import '../models/fish_sample.dart';

class LocalStore {
  static const _samplesKey = 'aqua_sense.samples.v1';
  static const _thresholdsKey = 'aqua_sense.thresholds.v1';
  static const _calibrationsKey = 'aqua_sense.calibrations.v1';

  Future<List<FishSample>> loadSamples() async {
    final preferences = await SharedPreferences.getInstance();
    final source = preferences.getString(_samplesKey);
    if (source == null || source.isEmpty) return [];
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Saved sample records are not a list.');
    }
    return decoded
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Saved sample record is invalid.');
          }
          return FishSample.fromJson(Map<String, dynamic>.from(value));
        })
        .toList(growable: true);
  }

  Future<void> saveSamples(List<FishSample> samples) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _samplesKey,
      jsonEncode(samples.map((sample) => sample.toJson()).toList()),
    );
  }

  Future<FreshnessThresholds> loadThresholds() async {
    final preferences = await SharedPreferences.getInstance();
    final source = preferences.getString(_thresholdsKey);
    if (source == null || source.isEmpty) return const FreshnessThresholds();
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Saved thresholds are invalid.');
    }
    return FreshnessThresholds.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> saveThresholds(FreshnessThresholds thresholds) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _thresholdsKey,
      jsonEncode(thresholds.toJson()),
    );
  }

  Future<List<Map<String, Object?>>> loadCalibrations() async {
    final preferences = await SharedPreferences.getInstance();
    final source = preferences.getString(_calibrationsKey);
    if (source == null || source.isEmpty) return [];
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Saved calibration records are invalid.');
    }
    return decoded
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Saved calibration record is invalid.');
          }
          return Map<String, Object?>.from(value);
        })
        .toList(growable: true);
  }

  Future<void> saveCalibration(Map<String, Object?> record) async {
    final records = await loadCalibrations();
    records.insert(0, record);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_calibrationsKey, jsonEncode(records));
  }
}
