import 'dart:typed_data';

class ImageAssetFormat {
  final String extension;
  final String mimeType;

  const ImageAssetFormat(this.extension, this.mimeType);
}

ImageAssetFormat detectImageAssetFormat(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return const ImageAssetFormat('png', 'image/png');
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return const ImageAssetFormat('jpg', 'image/jpeg');
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return const ImageAssetFormat('webp', 'image/webp');
  }
  return const ImageAssetFormat('bin', 'application/octet-stream');
}
