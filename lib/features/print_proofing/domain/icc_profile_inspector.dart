import 'dart:math';
import 'dart:typed_data';

import 'print_condition.dart';

class IccProfileInspection {
  final IccPrintProfileEvidence evidence;
  final PrintMediaWhitePoint? mediaWhitePoint;
  final List<String> problems;

  const IccProfileInspection({
    required this.evidence,
    required this.mediaWhitePoint,
    required this.problems,
  });

  bool get accepted => problems.isEmpty && evidence.isSupportedOutputProfile;
}

abstract final class IccProfileInspector {
  static IccProfileInspection inspect(
    Uint8List bytes, {
    required String fileName,
  }) {
    final problems = <String>[];
    if (bytes.length < 132) {
      return _invalid(fileName, bytes.length, 'Файл короче заголовка ICC.');
    }

    final data = ByteData.sublistView(bytes);
    final declaredSize = data.getUint32(0, Endian.big);
    final profileClass = _ascii(bytes, 12, 4);
    final dataColorSpace = _ascii(bytes, 16, 4);
    final connectionSpace = _ascii(bytes, 20, 4);
    final signature = _ascii(bytes, 36, 4);
    final version = _version(bytes);

    if (signature != 'acsp') {
      problems.add('Файл не содержит сигнатуру ICC «acsp».');
    }
    if (declaredSize < 132 || declaredSize > bytes.length) {
      problems.add('Размер ICC в заголовке не совпадает с файлом.');
    }
    if (profileClass != 'prtr') {
      problems.add('Нужен выходной профиль печати класса «prtr».');
    }
    if (dataColorSpace != 'CMYK') {
      problems.add(
          'Входное пространство профессионального профиля должно быть CMYK.');
    }
    if (connectionSpace != 'Lab ' && connectionSpace != 'XYZ ') {
      problems.add('Неподдерживаемое пространство связи профиля.');
    }

    final structurallyValid = signature == 'acsp' &&
        declaredSize >= 132 &&
        declaredSize <= bytes.length;
    final evidence = IccPrintProfileEvidence(
      fileName: fileName,
      sizeBytes: bytes.length,
      profileClass: profileClass,
      dataColorSpace: dataColorSpace,
      connectionSpace: connectionSpace,
      version: version,
      structurallyValid: structurallyValid,
    );
    return IccProfileInspection(
      evidence: evidence,
      mediaWhitePoint: structurallyValid ? _readMediaWhitePoint(bytes) : null,
      problems: List.unmodifiable(problems),
    );
  }

  static IccProfileInspection _invalid(
    String fileName,
    int sizeBytes,
    String problem,
  ) =>
      IccProfileInspection(
        evidence: IccPrintProfileEvidence(
          fileName: fileName,
          sizeBytes: sizeBytes,
          profileClass: '',
          dataColorSpace: '',
          connectionSpace: '',
          version: '',
          structurallyValid: false,
        ),
        mediaWhitePoint: null,
        problems: [problem],
      );

  static String _ascii(Uint8List bytes, int start, int length) =>
      String.fromCharCodes(bytes.sublist(start, start + length));

  static String _version(Uint8List bytes) {
    final major = bytes[8];
    final minor = bytes[9] >> 4;
    final bugfix = bytes[9] & 0x0F;
    return '$major.$minor.$bugfix';
  }

  static PrintMediaWhitePoint? _readMediaWhitePoint(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final tagCount = data.getUint32(128, Endian.big);
    if (tagCount > 4096 || 132 + tagCount * 12 > bytes.length) return null;
    for (var index = 0; index < tagCount; index++) {
      final entry = 132 + index * 12;
      if (_ascii(bytes, entry, 4) != 'wtpt') continue;
      final offset = data.getUint32(entry + 4, Endian.big);
      final size = data.getUint32(entry + 8, Endian.big);
      if (size < 20 ||
          offset + size > bytes.length ||
          offset + 20 > bytes.length) {
        return null;
      }
      if (_ascii(bytes, offset, 4) != 'XYZ ') return null;
      final x = _s15Fixed16(data, offset + 8);
      final y = _s15Fixed16(data, offset + 12);
      final z = _s15Fixed16(data, offset + 16);
      return _xyzD50ToLab(x, y, z);
    }
    return null;
  }

  static double _s15Fixed16(ByteData data, int offset) =>
      data.getInt32(offset, Endian.big) / 65536.0;

  static PrintMediaWhitePoint _xyzD50ToLab(double x, double y, double z) {
    double f(double value) {
      const epsilon = 216 / 24389;
      const kappa = 24389 / 27;
      return value > epsilon
          ? pow(value, 1 / 3).toDouble()
          : (kappa * value + 16) / 116;
    }

    final fx = f(x / 0.96422);
    final fy = f(y);
    final fz = f(z / 0.82521);
    return PrintMediaWhitePoint(
      l: 116 * fy - 16,
      a: 500 * (fx - fy),
      b: 200 * (fy - fz),
    );
  }
}
