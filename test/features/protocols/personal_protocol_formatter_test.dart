import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/protocols/protocols.dart';

void main() {
  test('formats a compact plain-text protocol for sharing', () {
    final text = PersonalProtocolFormatter.format(
      CheckProtocol(
        id: 'check-1',
        createdAt: DateTime(2026, 10, 9, 14, 5),
        score: 91.25,
        verdict: 'В норме',
        refSize: '100×100',
        cmpSize: '100×100',
        labId: 'lab-1',
        referenceLabel: 'Эталон 1',
        sampleLabel: 'Образец 2',
        labMatch: 98,
        stages: const [
          CheckProtocolStage(
            name: 'Цветовая карта ΔE*76',
            status: 'OK',
            metric: 'max 2,1 · среднее 0,8',
            comment: 'В норме',
          ),
          CheckProtocolStage(
            name: 'Геометрия ЧБ',
            status: 'OK',
            metric: '99,2%',
            comment: 'В норме',
          ),
          CheckProtocolStage(
            name: 'Время обработки',
            status: 'INFO',
            metric: '3,2 сек',
            comment: '',
          ),
        ],
      ),
    );

    expect(text, contains('TRIMATRIX · КРАТКИЙ ПРОТОКОЛ'));
    expect(text, contains('09.10.2026 · 14:05'));
    expect(text, contains('Сходство: 91,3%'));
    expect(text, contains('Цвет: max 2,1 · среднее 0,8'));
    expect(text, contains('Геометрия: 99,2%'));
    expect(text, isNot(contains('Время обработки')));
    expect(text, isNot(contains('Работа:')));
    expect(text, isNot(contains('Заказчик:')));
  });
}
