import 'admin_contracts.dart';
import 'package:neuro_core/neuro_core.dart';

String databaseEnum(Enum value) => value.name.replaceAllMapped(
  RegExp(r'[A-Z]'),
  (m) => '_${m[0]!.toLowerCase()}',
);
T directoryEnum<T extends Enum>(List<T> values, Object? value) =>
    values.firstWhere((v) => databaseEnum(v) == value);

final class ManagedPhysician {
  final String id, firstName, lastName, updatedAt;
  final String? email, userId;
  final DoctorRank rank;
  final Set<Capability> capabilities;
  final bool isActive;
  final int printOrder;
  const ManagedPhysician({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.updatedAt,
    this.email,
    this.userId,
    required this.rank,
    required this.capabilities,
    required this.isActive,
    required this.printOrder,
  });
  String get fullName => '$firstName $lastName';
}

final class ManagedViewer {
  final String id, displayName, updatedAt;
  final String? email;
  final ProfileLanguage language;
  final bool accessRevoked;
  const ManagedViewer({
    required this.id,
    required this.displayName,
    required this.updatedAt,
    this.email,
    required this.language,
    required this.accessRevoked,
  });
}

/// Commands retain their UUID for safe retries; version is the server timestamp.
final class DirectoryChange {
  final AdminWriteIntent operation;
  final String directory, id, updatedAt;
  final Map<String, Object?> changes;
  DirectoryChange({
    required this.operation,
    required this.directory,
    required this.id,
    required this.updatedAt,
    required Map<String, Object?> changes,
  }) : changes = Map.unmodifiable(changes);
}

final class DirectoryFailure implements Exception {
  final String code;
  final bool outcomeUnknown;
  const DirectoryFailure(this.code, {this.outcomeUnknown = false});
}

abstract interface class DirectoryAdministrationService
    implements InvitationUserAdministrationService {
  Future<List<ManagedPhysician>> physicians();
  Future<List<ManagedViewer>> viewers();
  Future<void> change(DirectoryChange request);
}
