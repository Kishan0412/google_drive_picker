import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;

/// Calls a global JS function whose LAST argument is a callback name.
/// The JS side must call window[callbackName](jsonStringOrNull) exactly once.
Future<String?> _invoke(String method, List<dynamic> args, {Duration timeout = const Duration(minutes: 5)}) {
  final completer = Completer<String?>();
  final callbackName = 'flutterDriveCb_${DateTime.now().microsecondsSinceEpoch}';

  js.context[callbackName] = (dynamic result) {
    if (!completer.isCompleted) completer.complete(result as String?);
  };

  js.context.callMethod(method, [...args, callbackName]);

  return completer.future.timeout(timeout, onTimeout: () => null).whenComplete(() {
    js.context.deleteProperty(callbackName);
  });
}

/// Opens the Google Picker UI. Returns picked files or null if cancelled.
Future<List<Map<String, dynamic>>?> openGooglePicker({
  required String accessToken,
  required String clientId,
  required String appId,
  required bool allowMultiple,
  String? initialQuery,
}) async {
  final raw = await _invoke('loadPicker', [accessToken, clientId, appId, allowMultiple, initialQuery ?? '']);
  if (raw == null) return null;

  final list = jsonDecode(raw) as List;
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

/// Gets an OAuth access token via Google Identity Services.
/// Returns JSON string: {"token": "...", "expiresIn": 3599} or null.
Future<String?> requestDriveAccessToken({required String clientId, required String scope}) {
  return _invoke('requestDriveToken', [clientId, scope], timeout: const Duration(minutes: 2));
}