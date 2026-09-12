import 'dart:typed_data';

class ChatAttachment {
  final String assetId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String organizationId;
  final String jobId;

  const ChatAttachment({
    required this.assetId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.organizationId,
    required this.jobId,
  });

  bool get isImage => mimeType.toLowerCase().startsWith('image/');

  static ChatAttachment? fromMetadata(Map<String, dynamic> metadata) {
    final assetId = metadata['asset_id'] as String? ?? '';
    final fileName = metadata['file_name'] as String? ?? '';
    final mimeType = metadata['mime_type'] as String? ?? '';
    final organizationId = metadata['organization_id'] as String? ?? '';
    final jobId = metadata['job_id'] as String? ?? '';
    final rawSize = metadata['size_bytes'];
    final sizeBytes = rawSize is int
        ? rawSize
        : rawSize is num
            ? rawSize.toInt()
            : int.tryParse(rawSize?.toString() ?? '') ?? 0;
    if (assetId.isEmpty ||
        fileName.isEmpty ||
        mimeType.isEmpty ||
        organizationId.isEmpty ||
        jobId.isEmpty ||
        sizeBytes < 0) {
      return null;
    }
    return ChatAttachment(
      assetId: assetId,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      organizationId: organizationId,
      jobId: jobId,
    );
  }

  Map<String, dynamic> toMetadata() => {
        'asset_id': assetId,
        'file_name': fileName,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'organization_id': organizationId,
        'job_id': jobId,
      };
}

class ChatAttachmentUpload {
  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  const ChatAttachmentUpload({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });
}
