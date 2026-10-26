import 'saved_reference.dart';

abstract interface class JobReferenceRepository {
  Future<SavedReferenceProfile?> loadActive({
    required String organizationId,
    required String jobId,
  });

  Future<SavedReferenceProfile> saveActive({
    required String organizationId,
    required String jobId,
    required SavedReferenceProfile reference,
  });
}
