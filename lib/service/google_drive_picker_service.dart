import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

// Web implementation by default; stub for Android / iOS.
import 'drive_picker_dialog.dart';
import 'google_drive_picker_stub.dart' if (dart.library.html) 'google_drive_picker_web.dart';

// ─── Config ──────────────────────────────────────────────────────────────────
// Web: drive.file is enough because the Google Picker grants per-file access.
const _webScope = 'https://www.googleapis.com/auth/drive.file';

// Mobile: we list/search files ourselves with files.list. With drive.file that
// call only returns files this app created/opened, so to search the user's whole
// Drive you need drive.readonly (restricted scope -> needs Google verification
// for production). Switch to drive.file if you only want app-created files.
const _mobileScopes = [_webScope];

// OAuth "Web application" client ID (used by web + as serverClientId on Android)
const _webClientId = '81987916165-mh4oa15kcgn57p247eoqekf507n1o2e9.apps.googleusercontent.com';
const _appId = '81987916165';

class DrivePickedFile {
  final String id;
  final String name;
  final String? mimeType;
  final Uint8List? bytes;

  DrivePickedFile({required this.id, required this.name, this.mimeType, this.bytes});
}

class DriveFilesPage {
  final List<DrivePickedFile> files;
  final String? nextPageToken;

  DriveFilesPage(this.files, this.nextPageToken);
}

class GoogleDrivePickerService {
  static final GoogleDrivePickerService _instance = GoogleDrivePickerService._internal();

  factory GoogleDrivePickerService() => _instance;

  GoogleDrivePickerService._internal();

  GoogleSignInAccount? _driveAccount;
  bool _initialized = false;

  String? _cachedAccessToken;
  DateTime? _tokenExpiry;

  bool get _isTokenValid => _cachedAccessToken != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!);

  // ── Auth ───────────────────────────────────────────────────────────────────
  Future<String?> _getAccessToken({bool forceRefresh = false}) async {
    if (!forceRefresh && _isTokenValid) return _cachedAccessToken;

    String? accessToken;
    Duration lifetime = const Duration(minutes: 50);

    if (kIsWeb) {
      // Google Identity Services token client: does NOT touch your Firebase
      // session, so phone-auth users stay signed in as themselves.
      final raw = await requestDriveAccessToken(clientId: _webClientId, scope: _webScope);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        accessToken = json['token'] as String?;
        final expiresIn = int.tryParse('${json['expiresIn']}');
        if (expiresIn != null) lifetime = Duration(seconds: expiresIn - 300);
      }
    } else {
      if (!_initialized) {
        // serverClientId is required on Android; iOS reads GoogleService-Info.plist
        await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
        _initialized = true;
      }

      try {
        _driveAccount = await GoogleSignIn.instance.attemptLightweightAuthentication()?.timeout(const Duration(seconds: 3));
      } catch (_) {
        _driveAccount = null;
      }

      if (_driveAccount != null) {
        try {
          final authorization = await _driveAccount!.authorizationClient.authorizationForScopes(_mobileScopes);
          accessToken = authorization?.accessToken;
        } catch (_) {}
      }

      if (accessToken == null) {
        try {
          _driveAccount ??= await GoogleSignIn.instance.authenticate(scopeHint: _mobileScopes);
          final authorization = await _driveAccount!.authorizationClient.authorizeScopes(_mobileScopes);
          accessToken = authorization.accessToken;
        } catch (e) {
          print('Drive auth failed: $e');
          return null;
        }
      }
    }

    if (accessToken != null) {
      _cachedAccessToken = accessToken;
      _tokenExpiry = DateTime.now().add(lifetime);
    }
    return accessToken;
  }

  void clearCache() {
    _cachedAccessToken = null;
    _tokenExpiry = null;
    _driveAccount = null;
    _initialized = false;
  }

  // ── Picker entry point ─────────────────────────────────────────────────────
  /// Web: native Google Picker (it has its own built-in search box; pass
  /// [initialQuery] to pre-fill a filter). Mobile: custom dialog with search.
  Future<List<DrivePickedFile>?> openPicker(BuildContext context, {bool allowMultiple = true, String? initialQuery}) async {
    final accessToken = await _getAccessToken();
    if (accessToken == null) return null;

    if (kIsWeb) {
      final results = await openGooglePicker(
        accessToken: accessToken,
        clientId: _webClientId,
        appId: _appId,
        allowMultiple: allowMultiple,
        initialQuery: initialQuery,
      );
      if (results == null || results.isEmpty) return null;

      final files = await Future.wait(
        results.map((file) async {
          final bytes = await _downloadFile(file['id'], file['mimeType'] ?? '', accessToken);
          return DrivePickedFile(id: file['id'], name: file['name'], mimeType: file['mimeType'], bytes: bytes);
        }),
      );
      return files;
    } else {
      final file = await showDialog<DrivePickedFile>(
        context: context,
        builder: (_) => DriveFilePickerDialog(service: this),
      );
      return file == null ? null : [file];
    }
  }

  // ── List + SEARCH ──────────────────────────────────────────────────────────
  /// Lists files, or searches by name when [query] is non-empty.
  /// Pass the returned nextPageToken back in as [pageToken] to load more.
  Future<DriveFilesPage> searchDriveFiles({String? query, String? pageToken, int pageSize = 30}) async {
    Future<DriveFilesPage> run(String token) async {
      final api = drive.DriveApi(_AuthClient(token));

      final conditions = <String>['trashed = false', "mimeType != 'application/vnd.google-apps.folder'"];
      final q = query?.trim() ?? '';
      if (q.isNotEmpty) conditions.add("name contains '${_escapeQuery(q)}'");

      final result = await api.files.list(
        q: conditions.join(' and '),
        pageSize: pageSize,
        pageToken: pageToken,
        spaces: 'drive',
        orderBy: 'modifiedTime desc',
        $fields: 'nextPageToken,files(id,name,mimeType)',
      );

      final files = (result.files ?? [])
          .where((f) => f.id != null && f.name != null)
          .map((f) => DrivePickedFile(id: f.id!, name: f.name!, mimeType: f.mimeType))
          .toList();
      return DriveFilesPage(files, result.nextPageToken);
    }

    final token = await _getAccessToken();
    if (token == null) return DriveFilesPage([], null);

    try {
      return await run(token);
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401) {
        // token expired/revoked -> refresh once and retry
        final fresh = await _getAccessToken(forceRefresh: true);
        if (fresh != null) return run(fresh);
      }
      rethrow;
    }
  }

  /// Drive query strings need \ and ' escaped.
  String _escapeQuery(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  Future<DrivePickedFile?> getFileById(String fileId) async {
    final accessToken = await _getAccessToken();
    if (accessToken == null) return null;

    final api = drive.DriveApi(_AuthClient(accessToken));
    final file = await api.files.get(fileId, $fields: 'id,name,mimeType') as drive.File;
    final bytes = await _downloadFile(fileId, file.mimeType ?? '', accessToken);

    return DrivePickedFile(id: file.id!, name: file.name!, mimeType: file.mimeType, bytes: bytes);
  }

  // ── Download ───────────────────────────────────────────────────────────────
  Future<Uint8List?> _downloadFile(String fileId, String mimeType, String accessToken) async {
    final headers = {'Authorization': 'Bearer $accessToken'};
    final exportMimeType = _getExportMimeType(mimeType);

    final Uri uri = exportMimeType != null
        ? Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId/export?mimeType=${Uri.encodeComponent(exportMimeType)}')
        : Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');

    final response = await http.get(uri, headers: headers);
    if (response.statusCode == 200) return response.bodyBytes;

    print('Drive download error: ${response.statusCode} ${response.body}');
    return null;
  }

  String? _getExportMimeType(String mimeType) {
    const exportMap = {
      'application/vnd.google-apps.document': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.google-apps.spreadsheet': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.google-apps.presentation': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'application/vnd.google-apps.drawing': 'image/png',
      'application/vnd.google-apps.script': 'application/json',
    };
    if (mimeType.startsWith('application/vnd.google-apps.')) {
      return exportMap[mimeType] ?? 'application/pdf';
    }
    return null;
  }

  // ── Upload ─────────────────────────────────────────────────────────────────
  Future<String?> uploadFile({required String fileName, required Uint8List bytes, String? mimeType}) async {
    final accessToken = await _getAccessToken();
    if (accessToken == null) return null;

    final api = drive.DriveApi(_AuthClient(accessToken));
    final driveFile = drive.File()..name = fileName;
    final media = drive.Media(Stream.value(bytes), bytes.length, contentType: mimeType ?? 'application/octet-stream');

    final uploaded = await api.files.create(driveFile, uploadMedia: media, $fields: 'id, name, webViewLink');
    return uploaded.webViewLink;
  }
}

class _AuthClient extends http.BaseClient {
  final String _token;
  final http.Client _inner = http.Client();

  _AuthClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }
}
