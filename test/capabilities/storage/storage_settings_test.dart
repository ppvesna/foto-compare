import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/capabilities/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('storage settings default to device-only without uploads', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = await StorageSettingsService.load();

    expect(settings.primaryLocation, AssetStorageLocation.device);
    expect(settings.syncProtocolMetadata, isFalse);
    expect(settings.syncPreviews, isFalse);
    expect(settings.syncOriginals, isFalse);
  });

  test('storage settings persist independently from authentication', () async {
    SharedPreferences.setMockInitialValues({});
    const selected = StorageSettings(
      primaryLocation: AssetStorageLocation.googleDrive,
      syncProtocolMetadata: true,
      syncPreviews: true,
      syncOriginals: false,
    );

    await StorageSettingsService.save(selected);
    final loaded = await StorageSettingsService.load();

    expect(loaded.primaryLocation, AssetStorageLocation.googleDrive);
    expect(loaded.syncProtocolMetadata, isTrue);
    expect(loaded.syncPreviews, isTrue);
    expect(loaded.syncOriginals, isFalse);
  });

  test('mock cloud storage supports a deterministic asset lifecycle', () async {
    final storage = MockCloudStorage();
    final connection = await storage.connect();
    final bytes = Uint8List.fromList([1, 2, 3]);

    final asset = await storage.upload(
      CloudAssetUpload(
        id: 'asset-1',
        name: 'reference.png',
        mimeType: 'image/png',
        bytes: bytes,
      ),
    );

    expect(connection.state, CloudConnectionState.connected);
    expect(asset.sizeBytes, 3);
    expect(await storage.download('asset-1'), bytes);

    await storage.delete('asset-1');
    expect(() => storage.download('asset-1'), throwsA(isA<StateError>()));
  });
}
