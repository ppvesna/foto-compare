import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/references/references.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReferenceStorage.profiles.value = const [];
  });

  test('loads an active reference and legacy layout profile JSON', () async {
    SharedPreferences.setMockInitialValues({
      'reference_profiles_v2': jsonEncode([_legacyReferenceJson()]),
      'reference_profiles_active_id_v2': 'reference-1',
    });

    final reference = await ReferenceStorage.loadActiveProfile();

    expect(reference, isNotNull);
    expect(reference!.id, 'reference-1');
    expect(reference.label, 'Эталон 1');
    expect(reference.bytes, [1, 2, 3, 4]);
    expect(reference.layoutProfile?.refAnchors.first.id, 'pt_0');
    expect(reference.layoutProfile?.cropRegion?.x, 0.1);
    expect(reference.layoutProfile?.cropRegion?.w, closeTo(0.8, 0.0001));
    expect(reference.layoutProfile?.reprojError, 1.25);
    expect(reference.layoutProfile?.widthMm, 120.0);
    expect(reference.layoutProfile?.heightMm, 80.0);
  });
}

Map<String, dynamic> _legacyReferenceJson() => {
      'id': 'reference-1',
      'label': 'Эталон 1',
      'bytes': base64Encode([1, 2, 3, 4]),
      'layoutProfile': {
        'id': 'profile-1',
        'name': 'Профиль 1',
        'refAnchors': [
          {'x': 0.1, 'y': 0.1},
          {'x': 0.9, 'y': 0.1},
          {'x': 0.9, 'y': 0.9},
          {'x': 0.1, 'y': 0.9},
        ],
        'homography': [1, 0, 0, 0, 1, 0, 0, 0, 1],
        'cropRegion': {
          'left': 0.1,
          'top': 0.2,
          'right': 0.9,
          'bottom': 0.8,
        },
        'widthMm': 120,
        'heightMm': 80,
        'reprojError': 1.25,
        'createdAt': '2026-07-01T10:00:00.000Z',
      },
      'createdAt': '2026-07-01T10:00:00.000Z',
    };
