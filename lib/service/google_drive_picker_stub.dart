// Used on Android / iOS. These are never called there (guarded by kIsWeb).

Future<List<Map<String, dynamic>>?> openGooglePicker({
  required String accessToken,
  required String clientId,
  required String appId,
  required bool allowMultiple,
  String? initialQuery,
}) async {
  return null;
}

Future<String?> requestDriveAccessToken({required String clientId, required String scope}) async {
  return null;
}