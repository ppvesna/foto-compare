import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_compare/capabilities/storage/storage.dart';

void main() {
  test('Google Drive adapter connects and keeps assets in Trimatrix folder',
      () async {
    var folderCreated = false;
    var assetCreated = false;
    var assetDeleted = false;
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer test-token');
      if (request.url.path == '/drive/v3/about') {
        return http.Response(
          jsonEncode({
            'user': {'emailAddress': 'user@example.com'},
          }),
          200,
        );
      }
      if (request.url.path == '/drive/v3/files' && request.method == 'GET') {
        final query = request.url.queryParameters['q'] ?? '';
        if (query.contains('mimeType')) {
          return http.Response(
            jsonEncode({
              'files': folderCreated
                  ? [
                      {'id': 'folder-1', 'name': 'Trimatrix'},
                    ]
                  : [],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'files': assetCreated && !assetDeleted
                ? [
                    {'id': 'file-1'},
                  ]
                : [],
          }),
          200,
        );
      }
      if (request.url.path == '/drive/v3/files' && request.method == 'POST') {
        folderCreated = true;
        return http.Response(jsonEncode({'id': 'folder-1'}), 200);
      }
      if (request.url.path == '/upload/drive/v3/files' &&
          request.method == 'POST') {
        expect(request.bodyBytes, containsAllInOrder([1, 2, 3]));
        assetCreated = true;
        return http.Response(
          jsonEncode({'id': 'file-1', 'name': 'reference.png', 'size': '3'}),
          200,
        );
      }
      if (request.url.path == '/drive/v3/files/file-1' &&
          request.method == 'GET') {
        return http.Response.bytes([1, 2, 3], 200);
      }
      if (request.url.path == '/drive/v3/files/file-1' &&
          request.method == 'DELETE') {
        assetDeleted = true;
        return http.Response('', 204);
      }
      return http.Response('not found', 404);
    });
    final authorization = _FakeGoogleDriveAuthorization();
    final storage = GoogleDriveCloudStorage(
      clientId: 'client-id',
      authorization: authorization,
      httpClient: client,
    );

    final connection = await storage.connect();
    expect(connection.state, CloudConnectionState.connected);
    expect(connection.accountLabel, 'user@example.com');

    final asset = await storage.upload(
      CloudAssetUpload(
        id: 'reference-1',
        name: 'reference.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    );
    expect(asset.storageKey, 'file-1');
    expect(await storage.download('reference-1'), [1, 2, 3]);

    await storage.delete('reference-1');
    expect(assetDeleted, isTrue);
    await storage.disconnect();
    expect(authorization.disconnected, isTrue);
  });

  test('Google Drive adapter reports missing OAuth configuration', () async {
    final storage = GoogleDriveCloudStorage(
      clientId: '',
      authorization: _FakeGoogleDriveAuthorization(configured: false),
      httpClient: MockClient((_) async => http.Response('', 500)),
    );

    final connection = await storage.connect();

    expect(connection.state, CloudConnectionState.error);
    expect(connection.errorMessage, contains('OAuth Client ID'));
  });
}

class _FakeGoogleDriveAuthorization implements GoogleDriveAuthorization {
  @override
  final bool configured;
  bool disconnected = false;

  _FakeGoogleDriveAuthorization({this.configured = true});

  @override
  Future<void> disconnect() async => disconnected = true;

  @override
  Future<Map<String, String>?> headers({
    required bool promptIfNecessary,
  }) async {
    if (!configured || disconnected) return null;
    return const {'Authorization': 'Bearer test-token'};
  }
}
