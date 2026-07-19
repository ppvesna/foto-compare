import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/app/local_access_testing_service.dart';
import 'package:photo_compare/features/billing/billing.dart';
import 'package:photo_compare/features/organization/organization.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves and loads a local access test override', () async {
    const expected = AccessTestOverride(
      enabled: true,
      plan: PlanTier.pro,
      role: OrganizationRole.operator,
    );
    const service = LocalAccessTestingService();

    await service.save(expected);
    final restored = await service.load();

    expect(restored.enabled, isTrue);
    expect(restored.plan, PlanTier.pro);
    expect(restored.role, OrganizationRole.operator);
  });

  test('invalid stored JSON falls back to disabled mode', () async {
    SharedPreferences.setMockInitialValues({
      'access_test_override_v1': '{invalid',
    });

    final restored = await const LocalAccessTestingService().load();

    expect(restored.enabled, isFalse);
    expect(restored.plan, PlanTier.free);
    expect(restored.role, OrganizationRole.personal);
  });
}
