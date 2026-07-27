import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/capabilities/storage/storage.dart';
import 'package:photo_compare/features/auth/auth.dart';
import 'package:photo_compare/features/billing/billing.dart';
import 'package:photo_compare/features/organization/organization.dart';
import 'package:photo_compare/screens/settings_screen.dart';

void main() {
  testWidgets('owner adds a nickname to the current account profile',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final profileService = MockAccountProfileService(
      profile: const AccountProfile(
        userId: 'owner-1',
        email: 'owner@example.com',
        nickname: '',
      ),
    );
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'vesna',
              role: OrganizationRole.owner,
            ),
            accountProfileService: profileService,
            onAccessChanged: () async => refreshCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Аккаунт'));
    await tester.pumpAndSettle();
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(find.text('Сбросить'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Ник'),
      'Owner_Vesna',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Имя'),
      'Олег',
    );
    await tester.tap(find.text('Сохранить профиль'));
    await tester.pumpAndSettle();

    expect(profileService.profile.nickname, 'owner_vesna');
    expect(profileService.profile.displayName, 'Олег');
    expect(profileService.saveCount, 1);
    expect(refreshCount, 1);
    expect(find.text('Профиль сохранён'), findsOneWidget);
  });

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
            cloudStorage: MockCloudStorage(),
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

    await tester.tap(
      find.byKey(const ValueKey('check-supabase-storage')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Облако доступно'), findsOneWidget);
    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Подключено: mock-account'), findsOneWidget);
  });

  testWidgets('owner prepares and sends an organization invitation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = MockOrganizationAdministrationService();
    final customerService = MockCustomerDirectoryService();

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
            customerDirectoryService: customerService,
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

  testWidgets('owner changes an active employee role to administrator',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = MockOrganizationAdministrationService(
      participants: [
        OrganizationParticipant(
          id: 'employee-1',
          userId: 'employee-1',
          email: 'ivan@example.com',
          nickname: 'printer_ivan',
          displayName: 'Иван',
          role: OrganizationRole.employee,
          functions: const {
            OrganizationMemberFunction.inspectionSpecialist,
          },
          status: OrganizationParticipantStatus.active,
          emailSent: true,
          createdAt: DateTime.utc(2026),
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
            customerDirectoryService: MockCustomerDirectoryService(),
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Организация').first);
    await tester.pumpAndSettle();
    expect(find.text('Изменить роль участника'), findsOneWidget);

    await tester
        .ensureVisible(find.byKey(const ValueKey('managed-member-selector')));
    await tester.tap(find.byKey(const ValueKey('managed-member-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('printer_ivan').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('managed-role-employee')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('managed-role-option-admin')).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить роль'));
    await tester.pumpAndSettle();

    expect(service.lastAssignment?.organizationId, 'organization-1');
    expect(service.lastAssignment?.userId, 'employee-1');
    expect(service.lastAssignment?.role, OrganizationRole.admin);
    expect(find.text('Роль сохранена'), findsOneWidget);
  });

  testWidgets('administrator cannot change another administrator',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = MockOrganizationAdministrationService(
      participants: [
        OrganizationParticipant(
          id: 'admin-2',
          userId: 'admin-2',
          email: 'admin@example.com',
          nickname: 'admin_two',
          displayName: 'Администратор 2',
          role: OrganizationRole.admin,
          functions: const {},
          status: OrganizationParticipantStatus.active,
          emailSent: true,
          createdAt: DateTime.utc(2026),
        ),
        OrganizationParticipant(
          id: 'employee-1',
          userId: 'employee-1',
          email: 'ivan@example.com',
          nickname: 'printer_ivan',
          displayName: 'Иван',
          role: OrganizationRole.employee,
          functions: const {},
          status: OrganizationParticipantStatus.active,
          emailSent: true,
          createdAt: DateTime.utc(2026),
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
              role: OrganizationRole.admin,
            ),
            organizationAdministrationService: service,
            customerDirectoryService: MockCustomerDirectoryService(),
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Организация').first);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('managed-member-selector')),
    );
    await tester.tap(find.byKey(const ValueKey('managed-member-selector')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('managed-member-admin-2')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('managed-member-employee-1')),
      findsOneWidget,
    );
    await tester.tap(find.text('printer_ivan').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('managed-role-employee')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('managed-role-option-admin')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('managed-role-option-customer')),
      findsOneWidget,
    );
  });

  testWidgets('administrator adds a customer to the organization directory',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final organizationService = MockOrganizationAdministrationService();
    final customerService = MockCustomerDirectoryService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              role: OrganizationRole.admin,
            ),
            organizationAdministrationService: organizationService,
            customerDirectoryService: customerService,
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Организация').first);
    await tester.pumpAndSettle();
    expect(find.text('Справочник заказчиков'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Код заказчика'),
      'VESNA',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Название заказчика'),
      'Типография Весна',
    );
    await tester.ensureVisible(find.text('Добавить заказчика'));
    await tester.tap(find.text('Добавить заказчика'));
    await tester.pumpAndSettle();

    expect(customerService.savedCustomer?.code, 'VESNA');
    expect(customerService.savedCustomer?.name, 'Типография Весна');
    expect(
      customerService.savedCustomer?.organizationId,
      'organization-1',
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
