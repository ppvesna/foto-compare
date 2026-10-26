import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../domain/cloud_storage.dart';
import '../domain/storage_settings.dart';

abstract interface class GoogleDriveAuthorization {
  bool get configured;

  Future<Map<String, String>?> headers({required bool promptIfNecessary});

  Future<void> disconnect();
}

class GoogleSignInDriveAuthorization implements GoogleDriveAuthorization {
  static const driveFileScope = 'https://www.googleapis.com/auth/drive.file';
  static Future<void>? _initialization;

  final String clientId;
  String? _accessToken;

  GoogleSignInDriveAuthorization(this.clientId);

  @override
  bool get configured => clientId.trim().isNotEmpty;

  @override
  Future<Map<String, String>?> headers({
    required bool promptIfNecessary,
  }) async {
    if (!configured) return null;
    _initialization ??= GoogleSignIn.instance.initialize(clientId: clientId);
    await _initialization;
    final result =
        await GoogleSignIn.instance.authorizationClient.authorizationHeaders(
      const [driveFileScope],
      promptIfNecessary: promptIfNecessary,
    );
    _accessToken = result?['Authorization']?.replaceFirst('Bearer ', '');
    return result;
  }

  @override
  Future<void> disconnect() async {
    final token = _accessToken;
    _accessToken = null;
    if (token == null || token.isEmpty) return;
    await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(
      accessToken: token,
    );
  }
}

class GoogleDriveCloudStorage implements CloudStorage {
  static const _apiHost = 'www.googleapis.com';
  static const _folderMimeType = 'application/vnd.google-apps.folder';
  static const _rootFolderName = 'Trimatrix';

  final GoogleDriveAuthorization authorization;
  final http.Client _http;

  String? _rootFolderId;
  String? _accountLabel;

  GoogleDriveCloudStorage({
    required String clientId,
    GoogleDriveAuthorization? authorization,
    http.Client? httpClient,
  })  : authorization =
            authorization ?? GoogleSignInDriveAuthorization(clientId),
        _http = httpClient ?? http.Client();

  bool get configured => authorization.configured;

  @override
  AssetStorageLocation get location => AssetStorageLocation.googleDrive;

  @override
  Future<CloudConnection> connection() => _probe(promptIfNecessary: false);

  @override
  Future<CloudConnection> connect() => _probe(promptIfNecessary: true);

  @override
  Future<void> disconnect() async {
    _rootFolderId = null;
    _accountLabel = null;
    await authorization.disconnect();
  }

  @override
  Future<CloudAsset> upload(CloudAssetUpload upload) async {
    _requirePersonalScope(upload.scope);
    final headers = await _requireHeaders();
    final folderId = await _ensureRootFolder(headers);
    final existingId = await _findAssetId(upload.id, headers, folderId);
    final boundary = 'trimatrix-${DateTime.now().microsecondsSinceEpoch}';
    final metadata = <String, Object>{
      'name': upload.name,
      'mimeType': upload.mimeType,
      if (existingId == null) 'parents': [folderId],
      'appProperties': {
        'trimatrixAssetId': upload.id,
        if (upload.checksum != null) 'checksum': upload.checksum!,
      },
    };
    final body = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(
          utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'))
      ..add(utf8.encode(jsonEncode(metadata)))
      ..add(utf8.encode('\r\n--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: ${upload.mimeType}\r\n\r\n'))
      ..add(upload.bytes)
      ..add(utf8.encode('\r\n--$boundary--'));
    final uri = Uri.https(
      _apiHost,
      existingId == null
          ? '/upload/drive/v3/files'
          : '/upload/drive/v3/files/$existingId',
      const {'uploadType': 'multipart', 'fields': 'id,name,size'},
    );
    final request = http.Request(existingId == null ? 'POST' : 'PATCH', uri)
      ..headers.addAll(headers)
      ..headers['Content-Type'] = 'multipart/related; boundary=$boundary'
      ..bodyBytes = body.takeBytes();
    final response = await http.Response.fromStream(await _http.send(request));
    _requireSuccess(response, operation: 'загрузка файла');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final fileId = data['id'] as String;
    return CloudAsset(
      id: upload.id,
      name: upload.name,
      mimeType: upload.mimeType,
      sizeBytes: upload.bytes.length,
      storageKey: fileId,
      scope: upload.scope,
      checksum: upload.checksum,
    );
  }

  @override
  Future<Uint8List> download(
    String assetId, {
    CloudAssetScope scope = const CloudAssetScope.personal(),
  }) async {
    _requirePersonalScope(scope);
    final headers = await _requireHeaders();
    final folderId = await _ensureRootFolder(headers);
    final fileId = await _findAssetId(assetId, headers, folderId);
    if (fileId == null) throw StateError('Google Drive file not found');
    final response = await _http.get(
      Uri.https(_apiHost, '/drive/v3/files/$fileId', const {'alt': 'media'}),
      headers: headers,
    );
    _requireSuccess(response, operation: 'загрузка файла из Google Drive');
    return response.bodyBytes;
  }

  @override
  Future<void> delete(
    String assetId, {
    CloudAssetScope scope = const CloudAssetScope.personal(),
  }) async {
    _requirePersonalScope(scope);
    final headers = await _requireHeaders();
    final folderId = await _ensureRootFolder(headers);
    final fileId = await _findAssetId(assetId, headers, folderId);
    if (fileId == null) return;
    final response = await _http.delete(
      Uri.https(_apiHost, '/drive/v3/files/$fileId'),
      headers: headers,
    );
    _requireSuccess(response, operation: 'удаление файла');
  }

  Future<CloudConnection> _probe({required bool promptIfNecessary}) async {
    if (!configured) {
      return const CloudConnection(
        state: CloudConnectionState.error,
        errorMessage: 'Google OAuth Client ID не задан.',
      );
    }
    try {
      final headers = await authorization.headers(
        promptIfNecessary: promptIfNecessary,
      );
      if (headers == null) return CloudConnection.disconnected;
      final response = await _http.get(
        Uri.https(
          _apiHost,
          '/drive/v3/about',
          const {'fields': 'user(displayName,emailAddress)'},
        ),
        headers: headers,
      );
      _requireSuccess(response, operation: 'проверка Google Drive');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final user = Map<String, dynamic>.from(data['user'] as Map? ?? const {});
      _accountLabel = (user['emailAddress'] as String?)?.trim();
      if (_accountLabel?.isEmpty ?? true) {
        _accountLabel = (user['displayName'] as String?)?.trim();
      }
      return CloudConnection(
        state: CloudConnectionState.connected,
        accountLabel: _accountLabel ?? 'Google Drive',
      );
    } catch (error) {
      return CloudConnection(
        state: CloudConnectionState.error,
        accountLabel: _accountLabel,
        errorMessage: error.toString(),
      );
    }
  }

  Future<Map<String, String>> _requireHeaders() async {
    final headers = await authorization.headers(promptIfNecessary: false);
    if (headers == null) {
      throw StateError('Google Drive is not connected');
    }
    return headers;
  }

  Future<String> _ensureRootFolder(Map<String, String> headers) async {
    final cached = _rootFolderId;
    if (cached != null) return cached;
    const query = "name = '$_rootFolderName' and "
        "mimeType = '$_folderMimeType' and trashed = false";
    final response = await _http.get(
      Uri.https(_apiHost, '/drive/v3/files', {
        'q': query,
        'spaces': 'drive',
        'fields': 'files(id,name)',
        'pageSize': '1',
      }),
      headers: headers,
    );
    _requireSuccess(response, operation: 'поиск папки Trimatrix');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files =
        (data['files'] as List? ?? const []).cast<Map<String, dynamic>>();
    if (files.isNotEmpty) {
      return _rootFolderId = files.first['id'] as String;
    }
    final createResponse = await _http.post(
      Uri.https(_apiHost, '/drive/v3/files', const {'fields': 'id'}),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': _rootFolderName,
        'mimeType': _folderMimeType,
      }),
    );
    _requireSuccess(createResponse, operation: 'создание папки Trimatrix');
    final created = jsonDecode(createResponse.body) as Map<String, dynamic>;
    return _rootFolderId = created['id'] as String;
  }

  Future<String?> _findAssetId(
    String assetId,
    Map<String, String> headers,
    String folderId,
  ) async {
    final escaped = assetId.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final query = "'$folderId' in parents and trashed = false and "
        "appProperties has { key='trimatrixAssetId' and value='$escaped' }";
    final response = await _http.get(
      Uri.https(_apiHost, '/drive/v3/files', {
        'q': query,
        'spaces': 'drive',
        'fields': 'files(id)',
        'pageSize': '1',
      }),
      headers: headers,
    );
    _requireSuccess(response, operation: 'поиск файла');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files =
        (data['files'] as List? ?? const []).cast<Map<String, dynamic>>();
    return files.isEmpty ? null : files.first['id'] as String;
  }

  void _requireSuccess(http.Response response, {required String operation}) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw StateError(
      'Google Drive: $operation не выполнена '
      '(${response.statusCode}).',
    );
  }

  void _requirePersonalScope(CloudAssetScope scope) {
    if (scope.type != CloudAssetScopeType.personal) {
      throw ArgumentError('Google Drive supports personal assets only');
    }
  }
}
