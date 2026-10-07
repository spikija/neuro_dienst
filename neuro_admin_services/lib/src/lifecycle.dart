import 'package:neuro_core/neuro_core.dart';

/// Intended semantics only. Current RLS does not enforce this policy.
abstract final class RosterLifecyclePolicy {
  static bool isPublishedPhase(RosterPhase phase) =>
      phase == RosterPhase.published;
  static bool allowsPhysicianSelection(RosterPhase phase) =>
      phase == RosterPhase.openForSelection;

  /// Locked corrections require an explicit, audited reason on the future RPC.
  /// Published schedules are corrected by creating a revision, never in-place.
  static bool allowsAdminAssignment(
    RosterPhase phase, {
    String? correctionReason,
  }) => switch (phase) {
    RosterPhase.draft || RosterPhase.openForSelection => true,
    RosterPhase.locked =>
      correctionReason != null && correctionReason.trim().isNotEmpty,
    RosterPhase.published => false,
  };

  /// Publish requires a locked, fully validated revision. This predicate alone
  /// does not authorize an operation or establish assignment completeness.
  static bool allowsTransition(RosterPhase from, RosterPhase to) =>
      switch ((from, to)) {
        (RosterPhase.draft, RosterPhase.openForSelection) ||
        (RosterPhase.draft, RosterPhase.locked) ||
        (RosterPhase.openForSelection, RosterPhase.locked) ||
        (RosterPhase.locked, RosterPhase.openForSelection) ||
        (RosterPhase.locked, RosterPhase.published) => true,
        _ => false,
      };
}

/// Optimistic concurrency stamp, distinct from the monthly revision number.
final class RosterVersion {
  final String rosterId;
  final int contentVersion;
  RosterVersion(this.rosterId, this.contentVersion) {
    if (rosterId.trim().isEmpty || contentVersion < 0) {
      throw ArgumentError(
        'Roster identity and non-negative content version required',
      );
    }
  }
}

/// Future versioned response; never synthesize these values from legacy rows.
final class RosterRevision {
  final RosterVersion version;
  final int year;
  final int month;
  final int revisionNumber;
  final RosterPhase phase;
  final String? supersedesRosterId;
  final bool isCurrentPublished;
  bool get isAuthoritative =>
      phase == RosterPhase.published && isCurrentPublished;
  RosterRevision({
    required this.version,
    required this.year,
    required this.month,
    required this.revisionNumber,
    required this.phase,
    this.supersedesRosterId,
    required this.isCurrentPublished,
  }) {
    if (year < 2000 ||
        year > 2100 ||
        month < 1 ||
        month > 12 ||
        revisionNumber < 1 ||
        (isCurrentPublished && phase != RosterPhase.published)) {
      throw ArgumentError('Invalid roster revision metadata');
    }
  }
}
