import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/capabilities/storage/storage.dart';
import 'package:photo_compare/features/auth/auth.dart';
import 'package:photo_compare/features/billing/billing.dart';
import 'package:photo_compare/features/organization/organization.dart';
import 'package:photo_compare/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('shows effective server plan, role, and capabilities',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
            onAccessChanged: () async {},
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
    expect(find.text('Тестирование доступа'), findsNothing);
    expect(find.text('Обновить права с сервера'), findsNothing);
  });

  testWidgets('shows why an expired Pro workspace uses Free capabilities',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final expiredAccess = EntitlementSnapshot.forPlan(PlanTier.free).copyWith(
      configuredPlan: PlanTier.pro,
      personalPlan: PlanTier.pro,
      scope: EntitlementScope.organization,
      organizationId: 'organization-1',
      validUntil: DateTime.utc(2026, 7, 30),
      subscriptionStatus: 'active',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: expiredAccess,
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'vesna',
              role: OrganizationRole.owner,
            ),
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Рабочий план'), findsOneWidget);
    expect(find.text('Тариф по подписке'), findsOneWidget);
    expect(find.text('30.07.2026'), findsNothing);
    expect(find.textContaining('истёк 30.07.2026'), findsOneWidget);
    expect(
      find.textContaining('применяются возможности бесплатного плана'),
      findsOneWidget,
    );
  });

  testWidgets('shows honest storage provider status without fake sync',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});

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

    await tester.tap(find.text('Облако приложения'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Протоколы и уменьшенные превью'),
      findsOneWidget,
    );
    final settings = await StorageSettingsService.load();
    expect(settings.primaryLocation, AssetStorageLocation.supabaseStorage);
    expect(settings.syncProtocolMetadata, isTrue);
    expect(settings.syncPreviews, isTrue);
    expect(settings.syncOriginals, isFalse);
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
    expect(find.byKey(const ValueKey('team-draft-row')), findsOneWidget);
    expect(find.text('Сохранить'), findsNothing);

    final fields = find.descendant(
      of: find.byKey(const ValueKey('team-draft-row')),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'ivan@example.com');
    await tester.enterText(fields.at(1), 'printer_ivan');
    await tester.enterText(fields.at(2), 'Иван Иванов');
    await tester.tap(find.byKey(const ValueKey('team-draft-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Пригласить сотрудника'));
    await tester.pumpAndSettle();

    expect(service.lastInvitation?.email, 'ivan@example.com');
    expect(service.lastInvitation?.nickname, 'printer_ivan');
    expect(service.lastInvitation?.role, OrganizationRole.employee);
    expect(
      service.lastInvitation?.functions,
      contains(OrganizationMemberFunction.inspectionSpecialist),
    );
  });

  testWidgets('owner invites a customer representative from customers tab',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = MockOrganizationAdministrationService();
    final customerService = MockCustomerDirectoryService(
      customers: [
        OrganizationCustomer(
          id: 'customer-1',
          organizationId: 'organization-1',
          code: 'CLIENT-1',
          name: 'Заказчик 1',
          active: true,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
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
            customerDirectoryService: customerService,
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Организация').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Заказчики'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Действия с заказчиком'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Пригласить представителя'));
    await tester.pumpAndSettle();
    final invitationFields = find.byType(TextField);
    await tester.enterText(invitationFields.at(2), 'client@example.com');
    await tester.enterText(invitationFields.at(3), 'client_user');
    await tester.enterText(invitationFields.at(4), 'Представитель');
    await tester.tap(find.text('Пригласить').last);
    await tester.pumpAndSettle();

    expect(service.lastInvitation?.role, OrganizationRole.customer);
    expect(service.lastInvitation?.nickname, 'client_user');
    expect(service.lastInvitation?.customerId, 'customer-1');
  });

  testWidgets('owner links an existing customer account from the row menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final organizationService = MockOrganizationAdministrationService(
      participants: [
        OrganizationParticipant(
          id: 'customer-member-1',
          userId: 'customer-user-1',
          email: 'customer@example.com',
          nickname: 'employee_test3',
          displayName: 'Тестовый заказчик',
          role: OrganizationRole.customer,
          functions: const {},
          status: OrganizationParticipantStatus.active,
          emailSent: true,
          createdAt: DateTime.utc(2026),
        ),
      ],
    );
    final customerService = MockCustomerDirectoryService(
      customers: [
        OrganizationCustomer(
          id: 'customer-1',
          organizationId: 'organization-1',
          code: 'CLIENT-1',
          name: 'Заказчик 1',
          active: true,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
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
    await tester.tap(find.text('Заказчики'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Действия с заказчиком'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать зарегистрированного'));
    await tester.pumpAndSettle();
    expect(find.text('employee_test3'), findsOneWidget);
    await tester.tap(find.text('Подключить'));
    await tester.pumpAndSettle();

    expect(customerService.savedCustomer?.customerId, 'customer-1');
    expect(customerService.savedCustomer?.customerUserId, 'customer-user-1');
  });

  testWidgets('owner can restore an archived customer', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final customerService = MockCustomerDirectoryService(
      customers: [
        OrganizationCustomer(
          id: 'archived-customer',
          organizationId: 'organization-1',
          code: 'OLD',
          name: 'Архивный заказчик',
          active: false,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
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
            organizationAdministrationService:
                MockOrganizationAdministrationService(),
            customerDirectoryService: customerService,
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Организация').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Заказчики'));
    await tester.pumpAndSettle();
    expect(find.text('Архивный заказчик'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Архивный заказчик'), findsOneWidget);
    await tester.tap(find.byTooltip('Действия с заказчиком'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Восстановить из архива'));
    await tester.pumpAndSettle();

    expect(customerService.restoredCustomerId, 'archived-customer');
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
    await tester.tap(find.byTooltip('Действия с участником'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить роль и функции'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-edit-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Администратор').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-edit-save')));
    await tester.pumpAndSettle();

    expect(service.lastMemberUpdate?.organizationId, 'organization-1');
    expect(service.lastMemberUpdate?.userId, 'employee-1');
    expect(service.lastMemberUpdate?.role, OrganizationRole.admin);
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

    final adminActions = find.descendant(
      of: find.byKey(const ValueKey('team-row-admin-2')),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuButton),
    );
    final employeeActions = find.descendant(
      of: find.byKey(const ValueKey('team-row-employee-1')),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuButton),
    );
    final adminButton = tester.widget(adminActions) as dynamic;
    final employeeButton = tester.widget(employeeActions) as dynamic;
    expect(adminButton.enabled, false);
    expect(employeeButton.enabled, true);
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
    await tester.tap(find.text('Заказчики'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('customer-draft-row')), findsOneWidget);

    final customerFields = find.descendant(
      of: find.byKey(const ValueKey('customer-draft-row')),
      matching: find.byType(TextField),
    );
    await tester.enterText(customerFields.at(0), 'VESNA');
    await tester.enterText(customerFields.at(1), 'Типография Весна');
    await tester.tap(find.byKey(const ValueKey('customer-draft-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать заказчика'));
    await tester.pumpAndSettle();

    expect(customerService.savedCustomer?.code, 'VESNA');
    expect(customerService.savedCustomer?.name, 'Типография Весна');
    expect(
      customerService.savedCustomer?.organizationId,
      'organization-1',
    );
  });

  testWidgets('customer edit tolerates an unavailable linked participant',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final organizationService = MockOrganizationAdministrationService(
      participants: [
        OrganizationParticipant(
          id: 'customer-member-1',
          userId: 'customer-user-1',
          email: 'customer@example.com',
          nickname: 'customer_one',
          displayName: 'Заказчик',
          role: OrganizationRole.customer,
          functions: const {},
          status: OrganizationParticipantStatus.active,
          emailSent: true,
          createdAt: DateTime.utc(2026),
        ),
      ],
    );
    final customerService = MockCustomerDirectoryService(
      customers: [
        OrganizationCustomer(
          id: 'customer-1',
          organizationId: 'organization-1',
          code: 'TEST',
          name: 'Тестовый заказчик',
          active: true,
          customerUserId: 'unavailable-user',
          customerUserNickname: 'old_customer',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
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
    expect(find.text('Тестовый заказчик'), findsNothing);
    await tester.tap(find.text('Заказчики'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Действия с заказчиком'));
    await tester.tap(find.byTooltip('Действия с заказчиком'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final draftFields = find.descendant(
      of: find.byKey(const ValueKey('customer-draft-row')),
      matching: find.byType(TextField),
    );
    expect(
        tester.widget<TextField>(draftFields.at(0)).controller?.text, 'TEST');
    await tester.tap(find.byKey(const ValueKey('customer-draft-actions')));
    await tester.pumpAndSettle();
    expect(find.text('Сохранить изменения'), findsOneWidget);
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

  testWidgets('owner activates an organization plan from billing settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paymentService = MockPaymentService(
      profile: const BillingProfile(
        billingEmail: 'billing@vesna.example',
        legalName: 'Vesna',
      ),
    );
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.free),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'vesna',
              role: OrganizationRole.owner,
            ),
            paymentService: paymentService,
            onAccessChanged: () async => refreshCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Тариф и оплата'));
    await tester.pumpAndSettle();
    expect(find.text('Тариф организации'), findsOneWidget);
    expect(find.text('29 €'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Номер карты'),
      findsNothing,
    );
    expect(find.widgetWithText(TextField, 'CVV'), findsNothing);

    await tester.tap(find.text('Год'));
    await tester.pumpAndSettle();
    expect(find.text('290 €'), findsOneWidget);

    await tester.tap(find.text('Активировать тестовую подписку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Да'));
    await tester.pumpAndSettle();

    expect(paymentService.lastScope, BillingScope.organization);
    expect(paymentService.lastOrganizationId, 'organization-1');
    expect(paymentService.lastActivation?.period, BillingPeriod.year);
    expect(refreshCount, 1);
    expect(find.text('Тариф активирован'), findsOneWidget);
  });

  testWidgets('administrator cannot manage the organization subscription',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paymentService = MockPaymentService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'vesna',
              role: OrganizationRole.admin,
            ),
            paymentService: paymentService,
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Тариф и оплата'));
    await tester.pumpAndSettle();

    expect(find.text('Тариф организации'), findsNothing);
    expect(find.textContaining('управляет только владелец'), findsOneWidget);
    expect(paymentService.lastScope, BillingScope.personal);
    expect(paymentService.lastOrganizationId, isNull);
  });
}
