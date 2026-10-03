import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/chat/chat.dart';
import 'package:photo_compare/screens/chat_screen.dart';

void main() {
  testWidgets('chat loads server threads and sends a message', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockChatRepository(
      currentUserId: 'user-1',
      currentNickname: 'printer_ivan',
      currentDisplayName: 'Иван',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            currentUserId: 'user-1',
            email: 'ivan@example.com',
            displayName: 'Иван',
            nickname: 'printer_ivan',
            organizationName: 'Vesna',
            chatRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Личные заметки'), findsWidgets);
    expect(
      find.byKey(const ValueKey('chat-section-service')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('chat-message-input')),
      'Проверка готова',
    );
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pumpAndSettle();

    expect(find.text('Проверка готова'), findsOneWidget);
    final threads = await repository.listThreads();
    final messages = await repository.listMessages(threads.single.id);
    expect(messages.single.text, 'Проверка готова');
  });

  testWidgets('administrator connects the customer from the work chat header',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockChatRepository(
      currentUserId: 'manager-1',
      currentNickname: 'manager_anna',
      currentDisplayName: 'Анна',
      threads: [
        ChatThread(
          id: 'job-customer-154',
          title: 'Работа № 154',
          kind: ChatThreadKind.jobCustomer,
          organizationId: 'organization-1',
          jobId: 'job-154',
          customerName: 'ООО Ромашка',
          customerShared: false,
          canManageCustomerAccess: true,
          updatedAt: DateTime.utc(2026, 10, 3, 12),
        ),
        ChatThread(
          id: 'job-internal-154',
          title: 'Работа № 154 · производство',
          kind: ChatThreadKind.jobInternal,
          organizationId: 'organization-1',
          jobId: 'job-154',
          customerName: 'ООО Ромашка',
          customerShared: false,
          canManageCustomerAccess: true,
          updatedAt: DateTime.utc(2026, 10, 3, 11),
        ),
      ],
      customerShareCandidates: [
        const CustomerShareCandidate(
          jobId: 'job-154',
          jobNumber: '154',
          customerName: 'ООО Ромашка',
          customerShared: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            currentUserId: 'manager-1',
            email: 'anna@example.com',
            displayName: 'Анна',
            nickname: 'manager_anna',
            organizationName: 'Vesna',
            canManageCustomerChatAccess: true,
            chatRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('current-customer-access-toggle')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('confirm-customer-access-change')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('Заказчик подключён'),
      findsOneWidget,
    );
    expect(
      (await repository.listCustomerShareCandidates()).single.customerShared,
      isTrue,
    );
  });

  testWidgets('job participant sends an ordinary attachment', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockChatRepository(
      currentUserId: 'customer-1',
      currentNickname: 'customer_sergey',
      currentDisplayName: 'Сергей',
      threads: [
        ChatThread(
          id: 'job-chat-2',
          title: 'Работа № VESNA-ISOLATION-TEST-002',
          kind: ChatThreadKind.jobCustomer,
          organizationId: 'organization-1',
          jobId: 'job-2',
          updatedAt: DateTime.utc(2026, 9, 12),
          customerShared: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            currentUserId: 'customer-1',
            email: 'sergey@example.com',
            displayName: 'Сергей',
            nickname: 'customer_sergey',
            organizationName: 'Vesna',
            chatRepository: repository,
            attachmentPicker: () async => ChatAttachmentUpload(
              fileName: 'sample.png',
              mimeType: 'image/png',
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('chat-message-input')),
      'Новый образец',
    );
    await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
    await tester.pumpAndSettle();
    final attachmentAction =
        find.byKey(const ValueKey('chat-file-attachment-action'));
    await tester.ensureVisible(attachmentAction);
    await tester.pumpAndSettle();
    await tester.tap(attachmentAction);
    await tester.pumpAndSettle();

    expect(find.text('Новый образец'), findsOneWidget);
    expect(find.text('sample.png'), findsOneWidget);
    expect(find.text('3 Б'), findsOneWidget);
    final messages = await repository.listMessages('job-chat-2');
    expect(messages.single.attachment?.fileName, 'sample.png');
  });

  testWidgets('administrator writes in the organization service chat',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockChatRepository(
      currentUserId: 'admin-1',
      currentNickname: 'admin_anna',
      currentDisplayName: 'Анна',
      threads: [
        ChatThread(
          id: 'service-chat-1',
          title: 'Служебные уведомления',
          kind: ChatThreadKind.service,
          organizationId: 'organization-1',
          updatedAt: DateTime.utc(2026, 10, 3),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            currentUserId: 'admin-1',
            email: 'anna@example.com',
            displayName: 'Анна',
            nickname: 'admin_anna',
            organizationName: 'Vesna',
            showOrganizationService: true,
            chatRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-message-input')), findsOneWidget);
    expect(find.text('служебный чат организации'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('chat-message-input')),
      'Проверка смены',
    );
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pumpAndSettle();
    expect(find.text('Проверка смены'), findsOneWidget);
  });

  testWidgets('organization staff sees service section before events',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockChatRepository(
      currentUserId: 'employee-1',
      currentNickname: 'employee_masha',
      currentDisplayName: 'Маша',
      threads: [
        ChatThread(
          id: 'personal-1',
          title: 'Личные заметки',
          kind: ChatThreadKind.personal,
          updatedAt: DateTime.utc(2026, 10, 3, 12),
        ),
        ChatThread(
          id: 'service-chat-1',
          title: 'Служебные',
          kind: ChatThreadKind.service,
          organizationId: 'organization-1',
          updatedAt: DateTime.utc(2026, 10, 3, 11),
        ),
      ],
      messages: const {
        'personal-1': [],
        'service-chat-1': [],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            currentUserId: 'employee-1',
            email: 'masha@example.com',
            displayName: 'Маша',
            nickname: 'employee_masha',
            organizationName: 'Vesna',
            showOrganizationService: true,
            chatRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat-section-service')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('chat-section-service')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('chat-message-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-attach-button')), findsOneWidget);
  });

  testWidgets('chat filters active unread archive and searches all jobs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockChatRepository(
      currentUserId: 'admin-1',
      currentNickname: 'admin_anna',
      currentDisplayName: 'Анна',
      threads: [
        ChatThread(
          id: 'personal-1',
          title: 'Личные заметки',
          kind: ChatThreadKind.personal,
          updatedAt: DateTime.utc(2026, 10, 3, 12),
        ),
        ChatThread(
          id: 'job-active',
          title: 'Работа № VESNA-ACTIVE-001',
          kind: ChatThreadKind.jobCustomer,
          organizationId: 'organization-1',
          jobId: 'job-active',
          jobStatus: 'active',
          customerName: 'Альфа',
          updatedAt: DateTime.utc(2026, 10, 3, 11),
        ),
        ChatThread(
          id: 'job-unread',
          title: 'Работа № VESNA-UNREAD-002',
          kind: ChatThreadKind.jobCustomer,
          organizationId: 'organization-1',
          jobId: 'job-unread',
          jobStatus: 'active',
          jobFlowState: 'blocked',
          customerName: 'Бета',
          unreadCount: 4,
          updatedAt: DateTime.utc(2026, 10, 3, 10),
        ),
        ChatThread(
          id: 'job-archive',
          title: 'Работа № VESNA-ARCHIVE-003',
          kind: ChatThreadKind.jobCustomer,
          organizationId: 'organization-1',
          jobId: 'job-archive',
          jobStatus: 'completed',
          customerName: 'Гамма',
          updatedAt: DateTime.utc(2026, 10, 2),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            currentUserId: 'admin-1',
            email: 'anna@example.com',
            displayName: 'Анна',
            nickname: 'admin_anna',
            organizationName: 'Vesna',
            chatRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-section-works')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Работа № VESNA-ACTIVE-001'), findsWidgets);
    expect(find.text('Работа № VESNA-UNREAD-002'), findsNothing);
    expect(find.text('Работа № VESNA-ARCHIVE-003'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-filter-unread')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Работа № VESNA-UNREAD-002'), findsWidgets);
    expect(find.text('Работа № VESNA-ACTIVE-001'), findsNothing);
    expect(find.text('Работа № VESNA-ARCHIVE-003'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-filter-archive')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Работа № VESNA-ARCHIVE-003'), findsWidgets);
    expect(find.textContaining('выполнена · Гамма'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('chat-search')),
      'Альфа',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Работа № VESNA-ACTIVE-001'), findsWidgets);
    expect(find.text('Работа № VESNA-ARCHIVE-003'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('chat-search')),
      'VESNA-ARCHIVE-003',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Работа № VESNA-ARCHIVE-003'), findsWidgets);
  });

  testWidgets('chat list refreshes when another thread changes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockChatRepository(
      currentUserId: 'admin-1',
      threads: [
        ChatThread(
          id: 'personal-1',
          title: 'Личные заметки',
          kind: ChatThreadKind.personal,
          updatedAt: DateTime.utc(2026, 10, 3),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            currentUserId: 'admin-1',
            email: 'anna@example.com',
            displayName: 'Анна',
            nickname: 'admin_anna',
            organizationName: 'Vesna',
            chatRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-section-works')));
    await tester.pumpAndSettle();

    repository.threads.add(
      ChatThread(
        id: 'job-live',
        title: 'Работа № VESNA-LIVE-004',
        kind: ChatThreadKind.jobCustomer,
        organizationId: 'organization-1',
        jobId: 'job-live',
        jobStatus: 'active',
        unreadCount: 1,
        updatedAt: DateTime.utc(2026, 10, 3, 13),
      ),
    );
    repository.notifyThreadChanged();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Работа № VESNA-LIVE-004'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-only-unread')), findsOneWidget);
  });

  testWidgets('personal search opens a direct dialog', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockChatRepository(
      currentUserId: 'admin-1',
      contacts: const [
        ChatContact(
          userId: 'employee-1',
          displayName: 'Маша',
          nickname: 'masha_check',
          roleLabel: 'Сотрудник',
          canAddToTeam: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            currentUserId: 'admin-1',
            email: 'anna@example.com',
            displayName: 'Анна',
            nickname: 'admin_anna',
            organizationName: 'Vesna',
            chatRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('chat-search')),
      'Маша',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('chat-contact-employee-1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Маша'), findsWidgets);
    expect(
      (await repository.listThreads())
          .singleWhere((thread) => thread.kind == ChatThreadKind.direct)
          .title,
      'Маша',
    );
  });

  testWidgets('work list opens one combined conversation with audiences',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockChatRepository(
      currentUserId: 'admin-1',
      threads: [
        ChatThread(
          id: 'personal-1',
          title: 'Личные заметки',
          kind: ChatThreadKind.personal,
          updatedAt: DateTime.utc(2026, 10, 3, 12),
        ),
        ChatThread(
          id: 'job-customer-1',
          title: 'Работа № VESNA-001',
          kind: ChatThreadKind.jobCustomer,
          organizationId: 'organization-1',
          jobId: 'job-1',
          customerName: 'Альфа',
          updatedAt: DateTime.utc(2026, 10, 3, 11),
        ),
        ChatThread(
          id: 'job-internal-1',
          title: 'Работа № VESNA-001 · производство',
          kind: ChatThreadKind.jobInternal,
          organizationId: 'organization-1',
          jobId: 'job-1',
          customerName: 'Альфа',
          updatedAt: DateTime.utc(2026, 10, 3, 10),
        ),
      ],
      messages: {
        'job-customer-1': [
          ChatMessage(
            id: 'customer-message-1',
            threadId: 'job-customer-1',
            senderId: 'admin-1',
            senderNickname: 'admin_anna',
            senderDisplayName: 'Анна',
            kind: ChatMessageKind.text,
            text: 'Видно заказчику',
            createdAt: DateTime.utc(2026, 10, 3, 10, 30),
          ),
        ],
        'job-internal-1': [
          ChatMessage(
            id: 'internal-message-1',
            threadId: 'job-internal-1',
            senderId: 'employee-1',
            senderNickname: 'employee_masha',
            senderDisplayName: 'Маша',
            kind: ChatMessageKind.text,
            text: 'Внутренняя запись',
            createdAt: DateTime.utc(2026, 10, 3, 10),
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            currentUserId: 'admin-1',
            email: 'anna@example.com',
            displayName: 'Анна',
            nickname: 'admin_anna',
            organizationName: 'Vesna',
            chatRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-section-works')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('open-work-chat-job-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('work-chat-group-job-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('work-chat-channel-job-customer-1')),
        findsNothing);
    expect(find.text('Внутренняя запись'), findsOneWidget);
    expect(find.text('Видно заказчику'), findsOneWidget);
    expect(find.text('Заказчику'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('work-audience-customer')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('chat-message-input')),
      'Новое заказчику',
    );
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pumpAndSettle();

    final customerMessages = await repository.listMessages('job-customer-1');
    expect(customerMessages.last.text, 'Новое заказчику');
    expect(
      await repository.listMessages('job-internal-1'),
      hasLength(1),
    );
  });

  testWidgets('team management is absent from the conversation screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockChatRepository(
      currentUserId: 'admin-1',
      contacts: const [
        ChatContact(
          userId: 'employee-1',
          displayName: 'Маша',
          nickname: 'masha_check',
          roleLabel: 'Сотрудник',
          canAddToTeam: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            currentUserId: 'admin-1',
            email: 'anna@example.com',
            displayName: 'Анна',
            nickname: 'admin_anna',
            organizationName: 'Vesna',
            chatRepository: repository,
            canManageTeams: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-section-teams')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('create-chat-team')), findsNothing);
    expect(
        repository.threads
            .where((thread) => thread.kind == ChatThreadKind.team),
        isEmpty);
  });
}
