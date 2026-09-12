import 'dart:typed_data';

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

  test('mock job chat sends and loads a private attachment', () async {
    final repository = MockChatRepository(
      currentUserId: 'customer-1',
      currentNickname: 'customer_sergey',
      currentDisplayName: 'Сергей',
      threads: [
        ChatThread(
          id: 'job-chat-2',
          title: 'Работа № VESNA-ISOLATION-TEST-002',
          kind: ChatThreadKind.job,
          organizationId: 'organization-1',
          jobId: 'job-2',
          updatedAt: DateTime.utc(2026, 9, 12),
          customerShared: true,
        ),
      ],
    );

    final sent = await repository.sendAttachment(
      threadId: 'job-chat-2',
      upload: ChatAttachmentUpload(
        fileName: 'sample.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      text: 'Новый образец',
    );

    expect(sent.kind, ChatMessageKind.image);
    expect(sent.attachment?.fileName, 'sample.png');
    expect(sent.attachment?.jobId, 'job-2');
    expect(await repository.loadAttachment(sent.attachment!), [1, 2, 3]);
  });
}
