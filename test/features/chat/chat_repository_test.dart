import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/chat/chat.dart';

void main() {
  test('mock chat creates a personal thread and sends a message', () async {
    final repository = MockChatRepository(
      currentUserId: 'user-1',
      currentNickname: 'printer_ivan',
      currentDisplayName: 'Иван',
    );

    await repository.ensureDefaultThreads();
    final threads = await repository.listThreads();
    final liveMessage = repository
        .watchMessages(threads.single.id)
        .firstWhere((messages) => messages.isNotEmpty);
    final sent = await repository.sendText(
      threadId: threads.single.id,
      text: 'Проверка готова',
    );
    final messages = await repository.listMessages(threads.single.id);

    expect(threads.single.kind, ChatThreadKind.personal);
    expect(sent.senderNickname, 'printer_ivan');
    expect(messages.single.text, 'Проверка готова');
    expect((await liveMessage).single.id, sent.id);
  });

  test('mock chat opens and closes a customer job thread', () async {
    final repository = MockChatRepository(
      customerShareCandidates: [
        const CustomerShareCandidate(
          jobId: 'job-154',
          jobNumber: '154',
          customerName: 'ООО Ромашка',
          customerShared: false,
        ),
      ],
    );

    await repository.ensureDefaultThreads();
    await repository.setCustomerAccess(jobId: 'job-154', shared: true);

    var candidates = await repository.listCustomerShareCandidates();
    var jobThread = (await repository.listThreads()).singleWhere(
      (thread) => thread.jobId == 'job-154',
    );
    expect(candidates.single.customerShared, isTrue);
    expect(jobThread.customerShared, isTrue);
    expect(jobThread.canManageCustomerAccess, isTrue);

    await repository.setCustomerAccess(jobId: 'job-154', shared: false);

    candidates = await repository.listCustomerShareCandidates();
    jobThread = (await repository.listThreads()).singleWhere(
      (thread) => thread.jobId == 'job-154',
    );
    expect(candidates.single.customerShared, isFalse);
    expect(jobThread.customerShared, isFalse);
  });
}
