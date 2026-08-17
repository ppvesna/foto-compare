import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_compare/features/protocols/protocols.dart';
import 'package:photo_compare/screens/chat_screen.dart';

void main() {
  testWidgets('chat opens an accessible cloud protocol from attach menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 430));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockProtocolCloudRepository();
    final preview = Uint8List.fromList(
      img.encodePng(img.Image(width: 32, height: 32)),
    );
    await repository.saveProtocol(
      CheckProtocol(
        id: 'protocol-1',
        createdAt: DateTime.utc(2026, 7, 27),
        jobId: 'job-1',
        jobNumber: '1001',
        score: 97.2,
        verdict: 'В норме',
        refSize: '100×100',
        cmpSize: '100×100',
        labId: 'abcd1234',
        sampleLabel: 'Отпечаток 1',
        labMatch: 99,
        stages: const [
          CheckProtocolStage(
            name: 'Цветовая карта ΔE00',
            status: 'OK',
            metric: 'max 2.1',
            comment: 'В норме',
          ),
        ],
      ),
      previewPng: preview,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            email: 'owner@example.com',
            displayName: 'Олег',
            nickname: 'owner',
            organizationName: 'Vesna',
            protocolCloudRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Технические данные'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
    await tester.pumpAndSettle();

    expect(find.text('Протокол проверки'), findsOneWidget);
    expect(find.text('Карта отличий'), findsOneWidget);
    await tester.tap(find.text('Протокол проверки'));
    await tester.pumpAndSettle();

    expect(find.textContaining('№ 1001'), findsWidgets);
    expect(find.textContaining('97.2%'), findsWidgets);
    expect(find.byType(Image), findsWidgets);
  });
}
