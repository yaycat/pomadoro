import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Signed out')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Anonymous';
    final uid = user?.uid ?? '';

    if (uid.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: Text('Not signed in')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'User: $email',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance
                  .ref('users/$uid/minutes')
                  .onValue,
              builder: (context, snap) {
                final val = snap.data?.snapshot.value;
                final minutes = (val as num?)?.toInt() ?? 0;
                return Text(
                  'Minutes: $minutes',
                  style: Theme.of(context).textTheme.bodyMedium,
                );
              },
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () => _signOut(context),
              child: const Text('Sign out'),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}
