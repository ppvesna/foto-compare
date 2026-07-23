import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/organization/organization.dart';
import 'package:photo_compare/features/production/production.dart';

void main() {
  final job = ProductionJob(
    id: 'job-125',
    organizationId: 'organization-1',
    number: '125',
    title: 'Этикетка',
    referenceId: 'reference-1',
    createdBy: 'owner-1',
    status: ProductionJobStatus.active,
    createdAt: DateTime(2026, 7, 20),
    updatedAt: DateTime(2026, 7, 20),
  );

  test('owner and administrator see every organization job', () {
    for (final role in [OrganizationRole.owner, OrganizationRole.admin]) {
      final access = JobAccessPolicy.resolve(
        job: job,
        currentUserId: 'user-1',
        organizationAccess: OrganizationAccess.forRole(
          organizationId: 'organization-1',
          role: role,
        ),
      );

      expect(access.allows(JobPermission.manageJob), isTrue);
      expect(access.allows(JobPermission.runInspection), isTrue);
    }
  });

  test('employee receives the union of assigned job functions', () {
    final access = JobAccessPolicy.resolve(
      job: job,
      currentUserId: 'employee-1',
      organizationAccess: OrganizationAccess.forRole(
        organizationId: 'organization-1',
        role: OrganizationRole.employee,
      ),
      participant: JobParticipant(
        jobId: job.id,
        userId: 'employee-1',
        functions: const {
          JobFunction.designer,
          JobFunction.inspectionSpecialist,
        },
        assignedAt: DateTime(2026, 7, 20),
      ),
    );

    expect(access.allows(JobPermission.uploadLayout), isTrue);
    expect(access.allows(JobPermission.runInspection), isTrue);
    expect(access.allows(JobPermission.manageParticipants), isFalse);
  });

  test('unassigned employee cannot see the job', () {
    final access = JobAccessPolicy.resolve(
      job: job,
      currentUserId: 'employee-1',
      organizationAccess: OrganizationAccess.forRole(
        organizationId: 'organization-1',
        role: OrganizationRole.employee,
      ),
    );

    expect(access.assigned, isFalse);
    expect(access.permissions, isEmpty);
  });

  test('assigned customer may approve but cannot edit or inspect', () {
    final access = JobAccessPolicy.resolve(
      job: job,
      currentUserId: 'customer-1',
      organizationAccess: OrganizationAccess.forRole(
        organizationId: 'organization-1',
        role: OrganizationRole.customer,
      ),
      participant: JobParticipant(
        jobId: job.id,
        userId: 'customer-1',
        functions: const {},
        assignedAt: DateTime(2026, 7, 20),
      ),
    );

    expect(access.allows(JobPermission.viewJob), isTrue);
    expect(access.allows(JobPermission.approveJob), isTrue);
    expect(access.allows(JobPermission.uploadLayout), isFalse);
    expect(access.allows(JobPermission.runInspection), isFalse);
  });
}
