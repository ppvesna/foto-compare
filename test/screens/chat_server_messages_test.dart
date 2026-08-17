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
}
