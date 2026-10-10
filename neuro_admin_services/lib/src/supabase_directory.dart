import 'package:neuro_core/neuro_core.dart';
import 'package:supabase/supabase.dart';
import 'admin_contracts.dart';
import 'directory.dart';

/// Shared adapter for both clients. No Auth admin API or privileged key.
class SupabaseDirectoryService implements DirectoryAdministrationService {
  final SupabaseClient client;
  SupabaseDirectoryService(this.client);
  Future<List<Map<String, dynamic>>> _rows(String kind) async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page =
          await client.rpc(
                'admin_directory',
                params: {'p_kind': kind, 'p_offset': offset, 'p_limit': 500},
              )
              as List;
      rows.addAll(page.cast<Map<String, dynamic>>());
      if (page.length < 500) return rows;
    }
  }

  @override
  Future<List<ManagedPhysician>> physicians() async => [
    for (final r in await _rows('physicians'))
      ManagedPhysician(
        id: r['id'],
        firstName: r['first_name'],
        lastName: r['last_name'],
        updatedAt: r['updated_at'],
        email: r['email'],
        userId: r['auth_user_id'],
        rank: directoryEnum(DoctorRank.values, r['rank']),
        capabilities: {
          for (final c in r['capabilities'])
            directoryEnum(Capability.values, c),
        },
        isActive: r['is_active'],
        printOrder: r['print_order'],
      ),
  ];
  @override
  Future<List<ManagedViewer>> viewers() async => [
    for (final r in await _rows('viewers'))
      ManagedViewer(
        id: r['id'],
        displayName: r['display_name'],
        updatedAt: r['updated_at'],
        email: r['email'],
        language: directoryEnum(
          ProfileLanguage.values,
          r['preferred_language'],
        ),
        accessRevoked: r['access_revoked'],
      ),
  ];
  @override
  Future<void> change(DirectoryChange request) async {
    try {
      final response =
          await client.rpc(
                'admin_manage_directory',
                params: {
                  'p_kind': request.directory,
                  'p_id': request.id,
                  'p_expected_updated_at': request.updatedAt,
                  'p_changes': request.changes,
                  'p_request_id': request.operation.requestId,
                },
              )
              as Map;
      if (response['error'] != null) throw DirectoryFailure(response['error']);
      if (response['success'] != true ||
          response['requestId'] != request.operation.requestId) {
        throw const DirectoryFailure('unavailable', outcomeUnknown: true);
      }
    } on DirectoryFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw DirectoryFailure(e.code ?? 'unavailable');
    } catch (_) {
      throw const DirectoryFailure('unavailable', outcomeUnknown: true);
    }
  }

  @override
  Future<InvitationReceipt> invite(InvitationRequest r) async {
    // The existing endpoint sends the email and does not support idempotency.
    // An uncertain response must be checked in the directory before retrying.
    try {
      final response = await client.functions.invoke(
        'invite-doctor',
        body: {
          'accountRole': r.accountRole.name,
          'email': r.email.trim(),
          'firstName': r.firstName.trim(),
          'lastName': r.lastName.trim(),
          'preferredLanguage': r.language.name,
          if (r.rank != null) 'rank': databaseEnum(r.rank!),
          'capabilities': r.capabilities.map(databaseEnum).toList(),
          if (r.accountRole == ManagedAccountRole.doctor)
            'isActive': r.isActive,
          if (r.accountRole == ManagedAccountRole.doctor &&
              r.printOrder != null)
            'printOrder': r.printOrder,
        },
      );
      if (response.status != 201 ||
          response.data is! Map ||
          response.data['accountRole'] != r.accountRole.name ||
          (r.accountRole == ManagedAccountRole.viewer
              ? response.data['doctorId'] != null
              : response.data['doctorId'] is! String ||
                    (response.data['doctorId'] as String).isEmpty)) {
        throw const DirectoryFailure('invitationUnknown', outcomeUnknown: true);
      }
      return InvitationReceipt(
        r.operation.requestId,
        r.accountRole,
        response.data['doctorId'],
        InvitationDeliveryStatus.sent,
      );
    } on DirectoryFailure {
      rethrow;
    } on FunctionException catch (e) {
      if (e.status >= 500) {
        throw const DirectoryFailure('invitationUnknown', outcomeUnknown: true);
      }
      if (e.status == 401) throw const DirectoryFailure('invalidSession');
      if (e.status == 403) throw const DirectoryFailure('adminAal2Required');
      if (r.accountRole == ManagedAccountRole.viewer &&
          e.details is Map &&
          e.details['error'] == 'The selected rank is invalid.') {
        throw const DirectoryFailure('invitationEndpointOutdated');
      }
      throw DirectoryFailure(
        e.status == 409 ? 'accountExists' : 'invitationFailed_${e.status}',
      );
    } catch (_) {
      throw const DirectoryFailure('invitationUnknown', outcomeUnknown: true);
    }
  }

  @override
  Future<void> updateProfile(UserProfileChange change) async {
    final row = (await viewers())
        .where((v) => v.id == change.userId)
        .firstOrNull;
    if (row == null) throw const DirectoryFailure('notFound');
    await this.change(
      DirectoryChange(
        operation: change.operation,
        directory: 'viewers',
        id: row.id,
        updatedAt: row.updatedAt,
        changes: {
          'display_name': change.displayName,
          'preferred_language': change.language.name,
        },
      ),
    );
  }
}
