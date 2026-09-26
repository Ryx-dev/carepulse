import 'package:flutter/material.dart';

import '../core/theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.name,
    required this.email,
    required this.onSignOut,
  });

  final String name;
  final String email;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Profile',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      const Text('Your CarePulse demo account', style: TextStyle(color: slate)),
      const SizedBox(height: 18),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: canvas,
                child: Icon(Icons.person_rounded, color: slate, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(email, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      Text(
        'Account settings',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline_rounded, color: coral),
              title: const Text('Name'),
              subtitle: Text(name),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.mail_outline_rounded, color: coral),
              title: const Text('Email address'),
              subtitle: Text(email),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            const ListTile(
              leading: Icon(Icons.info_outline_rounded, color: coral),
              title: Text('Account mode'),
              subtitle: Text('Local demo'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Account details are shown for this demo session only.',
        style: TextStyle(color: slate, fontSize: 12),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: onSignOut,
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryRed,
          side: const BorderSide(color: primaryRed),
          minimumSize: const Size.fromHeight(52),
        ),
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Sign out'),
      ),
    ],
  );
}
