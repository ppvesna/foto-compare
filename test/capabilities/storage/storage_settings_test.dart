import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/capabilities/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  test('Supabase asset paths are private and user-scoped', () {
    final storage = SupabaseCloudStorage(
      SupabaseClient('https://example.supabase.co', 'test-anon-key'),
      ownerUserId: 'user-1',
    );

    expect(storage.objectPath('asset-1'), 'users/user-1/asset-1');
    expect(
      () => storage.objectPath('../another-user/asset-1'),
      throwsArgumentError,
    );
    expect(
      storage.objectPath(
        'preview.png',
        scope: const CloudAssetScope.organizationJob(
          organizationId: 'organization-1',
          jobId: 'job-1',
        ),
      ),
      'organizations/organization-1/jobs/job-1/preview.png',
    );
  });

  test('mock cloud storage isolates personal and job assets', () async {
    final storage = MockCloudStorage();
    const scope = CloudAssetScope.organizationJob(
      organizationId: 'organization-1',
      jobId: 'job-1',
    );
    final bytes = Uint8List.fromList([4, 5, 6]);

    final asset = await storage.upload(
      CloudAssetUpload(
        id: 'preview.png',
        name: 'Preview',
        mimeType: 'image/png',
        bytes: bytes,
        scope: scope,
      ),
    );

    expect(
      asset.storageKey,
      'organizations/organization-1/jobs/job-1/preview.png',
    );
    expect(await storage.download('preview.png', scope: scope), bytes);
    expect(
      () => storage.download('preview.png'),
      throwsA(isA<StateError>()),
    );
  });
}
