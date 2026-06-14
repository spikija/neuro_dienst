import 'package:flutter/material.dart';

import 'admin_doctors_screen.dart';
import 'admin_role_templates_screen.dart';
import 'admin_rosters_screen.dart';
import 'admin_roles_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _AdminTile(
            icon: Icons.groups,
            title: 'Doctors',
            subtitle:
                'Manage doctor records, ranks, capabilities, and active status.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminDoctorsScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _AdminTile(
            icon: Icons.assignment_ind,
            title: 'Roles',
            subtitle:
                'Manage duty roles, abbreviations, rank rules, and capabilities.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminRolesScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _AdminTile(
            icon: Icons.event_repeat,
            title: 'Role templates',
            subtitle:
                'Define which roles create daily slots on which weekdays and times.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminRoleTemplatesScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _AdminTile(
            icon: Icons.calendar_month,
            title: 'Rosters',
            subtitle: 'Generate monthly roster days and slots from templates.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminRostersScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
