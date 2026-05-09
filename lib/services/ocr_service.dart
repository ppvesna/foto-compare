import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

class OcrBlock {
  final String text;
  final double left, top, right, bottom;
  const OcrBlock(this.text, this.left, this.top, this.right, this.bottom);
}

class OcrResult {
  final String fullText;
  final List<OcrBlock> blocks;
  final String? error; // null = успех, строка = причина сбоя
  const OcrResult(this.fullText, this.blocks, {this.error});
  bool get isEmpty => fullText.trim().isEmpty;
  bool get hasError => error != null;
}

class TextDiff {
  final List<String> missing;   // есть в эталоне, нет в фото
  final List<String> extra;     // есть в фото, нет в эталоне
  final double similarity;      // 0–100%

  const TextDiff({
    required this.missing,
    required this.extra,
    required this.similarity,
  });

  bool get allOk => missing.isEmpty && extra.isEmpty;
}

class OcrService {
  static Future<OcrResult> recognize(Uint8List bytes) async {
    File? tmp;
    TextRecognizer? recognizer;
    try {
      final dir = await getTemporaryDirectory();
      tmp = File('${dir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes(bytes);

      // latin охватывает латиницу + кириллицу в ML Kit v2
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(tmp.path);
      final recognized = await recognizer.processImage(inputImage);

      final blocks = recognized.blocks.map((b) => OcrBlock(
            b.text,
            b.boundingBox.left.toDouble(),
            b.boundingBox.top.toDouble(),
            b.boundingBox.right.toDouble(),
            b.boundingBox.bottom.toDouble(),
          )).toList();

      return OcrResult(recognized.text, blocks);
    } catch (e) {
      // Возвращаем ошибку для отображения в UI
      return OcrResult('', [], error: e.toString());
    } finally {
      await recognizer?.close();
      await tmp?.delete().catchError((_) {});
    }
  }

  static TextDiff compareTexts(String ref, String cmp) {
    final refWords = _tokenize(ref);
    final cmpWords = _tokenize(cmp);

    if (refWords.isEmpty && cmpWords.isEmpty) {
      return const TextDiff(missing: [], extra: [], similarity: 100);
    }
    if (refWords.isEmpty) {
      return TextDiff(missing: [], extra: cmpWords, similarity: 0);
    }
    if (cmpWords.isEmpty) {
      return TextDiff(missing: refWords, extra: [], similarity: 0);
    }

    final refFreq = <String, int>{};
    final cmpFreq = <String, int>{};
    for (final w in refWords) refFreq[w] = (refFreq[w] ?? 0) + 1;
    for (final w in cmpWords) cmpFreq[w] = (cmpFreq[w] ?? 0) + 1;

    int matched = 0;
    for (final w in refFreq.keys) {
      matched += _min(refFreq[w]!, cmpFreq[w] ?? 0);
    }

    final missing = <String>[];
    for (final w in refFreq.keys) {
      final diff = refFreq[w]! - (cmpFreq[w] ?? 0);
      for (int i = 0; i < diff; i++) missing.add(w);
    }

    final extra = <String>[];
    for (final w in cmpFreq.keys) {
      final diff = cmpFreq[w]! - (refFreq[w] ?? 0);
      for (int i = 0; i < diff; i++) extra.add(w);
    }

    final total = refWords.length + cmpWords.length;
    final similarity = (matched * 2 / total * 100).clamp(0.0, 100.0);

    return TextDiff(missing: missing, extra: extra, similarity: similarity);
  }

  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toList();
  }

  static int _min(int a, int b) => a < b ? a : b;
}
