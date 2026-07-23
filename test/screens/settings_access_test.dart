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
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
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

  testWidgets('owner finds a registered user and assigns an organization role',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = MockOrganizationAdministrationService(
      profilesByNickname: const {
        'printer_ivan': OrganizationUserProfile(
          userId: 'user-2',
          nickname: 'printer_ivan',
          displayName: 'Иван Иванов',
          organizationName: 'Тестовая типография',
        ),
      },
      members: [
        OrganizationMember(
          userId: 'owner-1',
          nickname: 'owner_oleg',
          displayName: 'Олег',
          role: OrganizationRole.owner,
          joinedAt: DateTime(2026, 7, 21),
        ),
      ],
    );

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
    expect(find.text('Найти пользователя по нику'), findsOneWidget);
    expect(find.text('owner_oleg'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'printer_ivan');
    await tester.tap(find.text('Найти пользователя'));
    await tester.pumpAndSettle();
    expect(find.text('Иван Иванов'), findsOneWidget);

    await tester.tap(find.text('Назначить или изменить роль'));
    await tester.pumpAndSettle();
    expect(service.lastAssignment?.userId, 'user-2');
    expect(service.lastAssignment?.role, OrganizationRole.employee);
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
