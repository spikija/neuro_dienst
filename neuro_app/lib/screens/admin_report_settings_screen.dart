import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_roster_service.dart';

class AdminReportSettingsScreen extends StatefulWidget {
  const AdminReportSettingsScreen({super.key});

  @override
  State<AdminReportSettingsScreen> createState() =>
      _AdminReportSettingsScreenState();
}

class _AdminReportSettingsScreenState extends State<AdminReportSettingsScreen> {
  late Future<List<ReportRole>> _rolesFuture;

  @override
  void initState() {
    super.initState();
    _rolesFuture = SupabaseRosterService().listReportRoles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report settings')),
      body: FutureBuilder<List<ReportRole>>(
        future: _rolesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _SettingsErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final roles = snapshot.data ?? [];

          if (roles.isEmpty) {
            return const Center(child: Text('No active roles found.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: roles.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final role = roles[index];

              return ListTile(
                leading: SizedBox(
                  width: 42,
                  child: Text(
                    '#${role.displayOrder}',
                    textAlign: TextAlign.right,
                  ),
                ),
                title: Text(role.name),
                subtitle: Text('${role.code} · Print in monthly A4 report'),
                trailing: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Move up in report',
                      onPressed: index == 0
                          ? null
                          : () => _swapDisplayOrder(
                              roles[index],
                              roles[index - 1],
                            ),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Move down in report',
                      onPressed: index == roles.length - 1
                          ? null
                          : () => _swapDisplayOrder(
                              roles[index],
                              roles[index + 1],
                            ),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    Checkbox(
                      value: role.printInReport,
                      onChanged: (value) => _setPrintInReport(
                        role: role,
                        printInReport: value ?? false,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _reload() {
    setState(() {
      _rolesFuture = SupabaseRosterService().listReportRoles();
    });
  }

  Future<void> _setPrintInReport({
    required ReportRole role,
    required bool printInReport,
  }) async {
    try {
      await SupabaseRosterService().updateRolePrintInReport(
        roleId: role.id,
        printInReport: printInReport,
      );
      _reload();
    } on PostgrestException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not update report setting.');
    }
  }

  Future<void> _swapDisplayOrder(
    ReportRole firstRole,
    ReportRole secondRole,
  ) async {
    final service = SupabaseRosterService();

    try {
      await service.updateRoleDisplayOrder(
        roleId: firstRole.id,
        displayOrder: secondRole.displayOrder,
      );
      await service.updateRoleDisplayOrder(
        roleId: secondRole.id,
        displayOrder: firstRole.displayOrder,
      );
      _reload();
    } on PostgrestException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not update report order.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SettingsErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _SettingsErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
