import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/billing/billing.dart';
import 'package:photo_compare/features/organization/organization.dart';
import 'package:photo_compare/screens/settings_screen.dart';

void main() {
  testWidgets('shows effective plan, role, capabilities, and test controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot(
              plan: PlanTier.pro,
              personalPlan: PlanTier.free,
              scope: EntitlementScope.organization,
              organizationId: 'organization-1',
              capabilities:
                  EntitlementSnapshot.forPlan(PlanTier.pro).capabilities,
              limits: EntitlementSnapshot.forPlan(PlanTier.pro).limits,
            ),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'vesna',
              role: OrganizationRole.employee,
            ),
            onAccessChanged: () async => refreshCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Текущий доступ'), findsOneWidget);
    expect(find.text('Личный план'), findsWidgets);
    expect(find.text('Рабочий план'), findsWidgets);
    expect(find.text('Бесплатный'), findsWidgets);
    expect(find.text('Pro'), findsWidgets);
    expect(find.text('Сотрудник'), findsWidgets);
    expect(find.text('vesna'), findsOneWidget);
    expect(find.text('Точная Delta E'), findsOneWidget);
    expect(find.text('Функции в конкретной работе'), findsOneWidget);
    expect(find.text('Менеджер'), findsOneWidget);
    expect(find.text('Дизайнер'), findsOneWidget);
    expect(find.text('Специалист проверки'), findsOneWidget);
    expect(find.text('Тестирование доступа'), findsOneWidget);

    await tester.tap(find.text('Обновить права с сервера'));
    await tester.pumpAndSettle();
    expect(refreshCount, 1);
  });

  testWidgets('shows honest storage provider status without fake sync',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              role: OrganizationRole.admin,
            ),
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Хранение'));
    await tester.pumpAndSettle();

    expect(find.text('Место хранения изображений'), findsOneWidget);
    expect(find.text('На устройстве пользователя'), findsOneWidget);
    expect(find.text('Облако приложения'), findsOneWidget);
    expect(find.text('Google Drive пользователя'), findsOneWidget);
    expect(find.text('Диск организации'), findsOneWidget);
    expect(find.text('Синхронизация с сервером'), findsNothing);
  });

  testWidgets('owner prepares and sends an organization invitation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = MockOrganizationAdministrationService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              role: OrganizationRole.owner,
            ),
            organizationAdministrationService: service,
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Организация').first);
    await tester.pumpAndSettle();
    expect(find.text('Пригласить участника'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'ivan@example.com');
    await tester.enterText(fields.at(1), 'printer_ivan');
    await tester.enterText(fields.at(2), 'Иван Иванов');
    await tester.tap(find.text('Сохранить и отправить приглашение'));
    await tester.pumpAndSettle();

    expect(service.lastInvitation?.email, 'ivan@example.com');
    expect(service.lastInvitation?.nickname, 'printer_ivan');
    expect(service.lastInvitation?.role, OrganizationRole.employee);
    expect(
      service.lastInvitation?.functions,
      contains(OrganizationMemberFunction.inspectionSpecialist),
    );
  });

  testWidgets('personal Pro user creates an organization and becomes owner',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = MockOrganizationAdministrationService();
    var accessRefreshes = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: null,
              role: OrganizationRole.personal,
            ),
            organizationAdministrationService: service,
            onAccessChanged: () async => accessRefreshes++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Организация').first);
    await tester.pumpAndSettle();
    expect(find.text('Создание организации'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Trimatrix Test Print');
    await tester.tap(find.text('Создать организацию'));
    await tester.pumpAndSettle();

    expect(service.lastCreatedOrganizationName, 'Trimatrix Test Print');
    expect(accessRefreshes, 1);
  });
}
