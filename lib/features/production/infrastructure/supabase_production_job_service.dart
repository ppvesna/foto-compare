import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/production_job_service.dart';

class SupabaseProductionJobService implements ProductionJobService {
  final SupabaseClient client;

  const SupabaseProductionJobService(this.client);

  @override
  Future<ProductionJobContext> openJob({
    required String organizationId,
    required String jobNumber,
    String? customerId,
    String? requestedCustomerName,
  }) async {
    final response = await client.rpc(
      'open_production_job_v1',
      params: {
        'target_organization': organizationId,
        'target_number': jobNumber.trim(),
        'target_customer': customerId,
        'target_requested_customer_name': requestedCustomerName?.trim(),
      },
    );
    if (response is! Map) {
      throw StateError('Supabase did not return the production job');
    }
    final row = Map<String, dynamic>.from(response);
    return ProductionJobContext(
      jobId: row['job_id'] as String,
      jobNumber: row['job_number'] as String? ?? jobNumber.trim(),
      customerId: row['customer_id'] as String?,
      customerName: row['customer_name'] as String? ?? '',
      customerConfirmed: row['customer_confirmed'] == true,
      customerRequestId: row['customer_request_id'] as String?,
    );
  }
}
