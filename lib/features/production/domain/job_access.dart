import '../../organization/organization.dart';
import 'production_job.dart';

enum JobFunction {
  manager,
  designer,
  inspectionSpecialist,
}

enum JobPermission {
  viewJob,
  manageJob,
  manageParticipants,
  uploadLayout,
  runInspection,
  manageReferences,
  viewProtocols,
  addComments,
  approveJob,
}

class JobParticipant {
  final String jobId;
  final String userId;
  final Set<JobFunction> functions;
  final DateTime assignedAt;

  const JobParticipant({
    required this.jobId,
    required this.userId,
    required this.functions,
    required this.assignedAt,
  });
}

class JobAccess {
  final bool assigned;
  final Set<JobFunction> functions;
  final Set<JobPermission> permissions;

  const JobAccess({
    required this.assigned,
    required this.functions,
    required this.permissions,
  });

  static const denied = JobAccess(
    assigned: false,
    functions: {},
    permissions: {},
  );

  bool allows(JobPermission permission) => permissions.contains(permission);
}

abstract final class JobAccessPolicy {
  static JobAccess resolve({
    required ProductionJob job,
    required String currentUserId,
    required OrganizationAccess organizationAccess,
    JobParticipant? participant,
  }) {
    if (organizationAccess.role == OrganizationRole.personal) {
      final ownsPersonalJob =
          job.organizationId == null && job.createdBy == currentUserId;
      return ownsPersonalJob ? _fullAccess() : JobAccess.denied;
    }

    if (job.organizationId == null ||
        job.organizationId != organizationAccess.organizationId) {
      return JobAccess.denied;
    }

    if (organizationAccess.role == OrganizationRole.owner ||
        organizationAccess.role == OrganizationRole.admin) {
      return _fullAccess();
    }

    final isAssigned = participant != null &&
        participant.jobId == job.id &&
        participant.userId == currentUserId;
    if (!isAssigned) return JobAccess.denied;

    if (organizationAccess.role == OrganizationRole.customer) {
      return const JobAccess(
        assigned: true,
        functions: {},
        permissions: {
          JobPermission.viewJob,
          JobPermission.viewProtocols,
          JobPermission.addComments,
          JobPermission.approveJob,
        },
      );
    }

    final permissions = <JobPermission>{
      JobPermission.viewJob,
      JobPermission.viewProtocols,
      JobPermission.addComments,
    };
    for (final function in participant.functions) {
      permissions.addAll(_permissionsForFunction(function));
    }
    return JobAccess(
      assigned: true,
      functions: Set.unmodifiable(participant.functions),
      permissions: permissions,
    );
  }

  static JobAccess _fullAccess() => JobAccess(
        assigned: true,
        functions: JobFunction.values.toSet(),
        permissions: JobPermission.values.toSet(),
      );

  static Set<JobPermission> _permissionsForFunction(JobFunction function) {
    switch (function) {
      case JobFunction.manager:
        return {
          JobPermission.manageJob,
          JobPermission.manageParticipants,
        };
      case JobFunction.designer:
        return {JobPermission.uploadLayout};
      case JobFunction.inspectionSpecialist:
        return {
          JobPermission.runInspection,
          JobPermission.manageReferences,
        };
    }
  }
}

extension JobFunctionLabel on JobFunction {
  String get label {
    switch (this) {
      case JobFunction.manager:
        return 'Менеджер';
      case JobFunction.designer:
        return 'Дизайнер';
      case JobFunction.inspectionSpecialist:
        return 'Специалист проверки';
    }
  }
}
