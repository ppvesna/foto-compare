import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/organization/organization.dart';
import 'package:photo_compare/features/production/production.dart';

void main() {
  test('customer directory mock records administrator changes', () async {
    final service = MockCustomerDirectoryService();

    final customerId = await service.saveCustomer(
      organizationId: 'organization-1',
      code: 'VESNA',
      name: 'Типография Весна',
      managerUserId: 'manager-1',
      customerUserId: 'customer-user-1',
    );

    expect(customerId, 'mock-customer-1');
    expect(service.savedCustomer?.managerUserId, 'manager-1');
    expect(service.savedCustomer?.customerUserId, 'customer-user-1');
  });

  test('production workflow keeps an unconfirmed customer request', () async {
    final service = MockProductionJobService();

    final job = await service.openJob(
      organizationId: 'organization-1',
      jobNumber: '15482',
      requestedCustomerName: 'Новый заказчик из ТЗ',
    );

    expect(service.lastOpenJob?.jobNumber, '15482');
    expect(job.customerConfirmed, isFalse);
    expect(job.customerName, 'Новый заказчик из ТЗ');
  });
}
