library redux_persist_flutter;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:redux_persist/redux_persist.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Location to save state when using Flutter.
enum FlutterSaveLocation {
  /// Maps to DocumentFileEngine.
  documentFile,

  /// Maps to SharedPreferencesEngine.
  sharedPreferences,
}

/// Storage engine to use with Flutter.
/// Proxy of SharedPreferenceEngine and DocumentFileEngine.
class FlutterStorage implements StorageEngine {
  late StorageEngine _locationEngine;

  FlutterStorage({
    String key = "app",
    FlutterSaveLocation location = FlutterSaveLocation.documentFile,
  }) {
    switch (location) {
      case FlutterSaveLocation.documentFile:
        _locationEngine = DocumentFileEngine(key);
        break;
      case FlutterSaveLocation.sharedPreferences:
        _locationEngine = SharedPreferencesEngine(key);
        break;
      default:
        throw StorageException("No Flutter storage location");
    }
  }

  @override
  Future<Uint8List?> load() => _locationEngine.load();

  @override
  Future<void> save(Uint8List? json) => _locationEngine.save(json);
}

/// Storage engine to save to application document directory.
class DocumentFileEngine implements StorageEngine {
  /// File name to save to.
  final String key;

  DocumentFileEngine([this.key = "app"]);

  @override
  Future<Uint8List?> load() async {
    return compute(_readFile, await _getFile());
  }

  @override
  Future<void> save(Uint8List? data) async {
    await compute(_saveFile, SaveFileParams(await _getFile(), data));
  }

  Future<File> _getFile() async {
    // Use the Flutter app documents directory
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/persist_$key.json');
  }
}

/// _readFile is intended to be called via a compute method to take off the main
/// thread
Future<Uint8List?> _readFile(File file) async {
  return await file.readAsBytes();
}

/// SaveFileParams convenience class to allow using compute
class SaveFileParams {
  final File file;
  final Uint8List? data;

  SaveFileParams(this.file, this.data);
}

/// _saveFile is intended to be called via a compute method to take off the main
/// thread
Future<void> _saveFile(SaveFileParams params) async {
  final data = params.data;
  if (data == null) {
    return;
  }
  await params.file.writeAsBytes(data);
}

/// Storage engine to save to NSUserDefaults/SharedPreferences.
/// You should only store utf8-encoded data here, like JSON, or base64 data.
class SharedPreferencesEngine implements StorageEngine {
  /// Shared preferences key to save to.
  final String key;

  SharedPreferencesEngine([this.key = "app"]);

  @override
  Future<Uint8List?> load() async {
    final sharedPreferences = await _getSharedPreferences();
    return stringToUint8List(sharedPreferences.getString(key));
  }

  @override
  Future<void> save(Uint8List? data) async {
    final sharedPreferences = await _getSharedPreferences();
    sharedPreferences.setString(key, await uint8ListToString(data) ?? '');
  }

  Future<SharedPreferences> _getSharedPreferences() async =>
      await SharedPreferences.getInstance();
}

class FlutterJsonSerializer<T> implements StateSerializer<T> {
  /// Turns the dynamic [json] (can be null) to [T]
  final T? Function(dynamic? json) decoder;

  FlutterJsonSerializer(this.decoder);

  @override
  Future<T?> decode(Uint8List? data) async {
    return decoder(
        data != null ? json.decode(await uint8ListToString(data) ?? '') : null);
  }

  @override
  Future<Uint8List?> encode(T state) async {
    if (state == null) {
      return null;
    }

    return stringToUint8List(await compute(jsonEncode, state));
  }
}

// String helpers

Future<Uint8List?> stringToUint8List(String? data) async {
  if (data == null) {
    return null;
  }

  return await compute(_utf8Encode, data);
}

Future<String?> uint8ListToString(Uint8List? data) async {
  if (data == null) {
    return null;
  }

  return await compute(_utf8Decode, data);
}

/// _utf8Decode is intended to be called by a compute.
String _utf8Decode(List<int> codeUnits) {
  // Switch between const objects to avoid allocation.
  Utf8Decoder decoder = const Utf8Decoder(allowMalformed: false);
  return decoder.convert(codeUnits);
}

/// _utf8Encode is intended to be called by a compute.
Uint8List _utf8Encode(String data) {
  Utf8Encoder utf8encoder = const Utf8Encoder();
  return utf8encoder.convert(data);
}
