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

  testWidgets('manager opens a job chat for the customer', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockChatRepository(
      currentUserId: 'manager-1',
      currentNickname: 'manager_anna',
      currentDisplayName: 'Анна',
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
            chatRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('customer-access-menu-action')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Работа № 154'), findsOneWidget);
    expect(find.text('ООО Ромашка'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('customer-access-toggle-job-154')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-customer-access-change')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('Работа доступна назначенному заказчику'),
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

  testWidgets('administrator service chat is read only', (tester) async {
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
            chatRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('service-chat-read-only')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-message-input')), findsNothing);
    expect(find.text('служебный журнал администратора'), findsWidgets);
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
    expect(find.text('Работа № VESNA-UNREAD-002'), findsOneWidget);
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
    expect(find.textContaining('архив · Гамма'), findsWidgets);

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
    expect(find.text('Непрочитанные · 1'), findsOneWidget);
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

  testWidgets('work list groups internal and customer channels',
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

    expect(
      find.byKey(const ValueKey('work-chat-group-job-1')),
      findsOneWidget,
    );
    expect(find.text('Производство'), findsOneWidget);
    expect(find.text('Заказчик'), findsOneWidget);
  });

  testWidgets('administrator creates a team from internal contacts',
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
    await tester.tap(find.byKey(const ValueKey('create-chat-team')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('chat-team-name')),
      'Смена тест',
    );
    await tester.tap(
      find.byKey(const ValueKey('chat-team-member-employee-1')),
    );
    await tester.tap(find.byKey(const ValueKey('save-chat-team')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Смена тест'), findsWidgets);
    expect(
      (await repository.listThreads())
          .singleWhere((thread) => thread.kind == ChatThreadKind.team)
          .canManage,
      isTrue,
    );
  });
}
