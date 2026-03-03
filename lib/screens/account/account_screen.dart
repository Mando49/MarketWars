import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart' as app;
import '../../theme/app_theme.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios,
                        size: 16, color: AppTheme.green),
                  ),
                  const SizedBox(width: 10),
                  const Text('Account Settings',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Content ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // ── SETTINGS section ──
                  const _SectionLabel('SETTINGS'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Column(
                        children: [
                          _ProfileRow(
                            icon: Icons.person_outline,
                            label: 'Username',
                            value: user?.displayName ?? 'Player',
                            onEdit: () => _showUsernameDialog(context, user),
                          ),
                          _ProfileRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone',
                            value: user?.phoneNumber ?? 'Not set',
                            onEdit: null,
                          ),
                          _ProfileRow(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: user?.email ?? 'Not set',
                            onEdit: null,
                          ),
                          _ProfileRow(
                            icon: Icons.lock_outline,
                            label: 'Password',
                            value: '••••••••',
                            onEdit: () => _showPasswordDialog(context),
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Terms of Service ──
                  _TappableRow(
                    icon: Icons.description_outlined,
                    label: 'Terms of Service',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const _LegalScreen(
                          title: 'Terms of Service',
                          content: _kTermsOfService,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Privacy Policy ──
                  _TappableRow(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const _LegalScreen(
                          title: 'Privacy Policy',
                          content: _kPrivacyPolicy,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Subscription ──
                  _TappableRow(
                    icon: Icons.star_outline,
                    label: 'Subscription',
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.greenDim,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('COMING SOON',
                          style: TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.green)),
                    ),
                    onTap: null,
                  ),

                  const SizedBox(height: 32),

                  // ── Sign Out ──
                  GestureDetector(
                    onTap: () => _confirmSignOut(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.redDim,
                        border: Border.all(
                            color: AppTheme.red.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text('Sign Out',
                            style: TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.red)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Username dialog ──
  void _showUsernameDialog(BuildContext context, User? user) {
    final ctrl = TextEditingController(text: user?.displayName ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Update Username',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(
              fontFamily: 'Courier', fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'New username',
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            filled: true,
            fillColor: AppTheme.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.green)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await user?.updateDisplayName(newName);
                await user?.reload();
                // Update Firestore profile too
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user?.uid)
                    .update({'username': newName});
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Username updated to $newName'),
                    backgroundColor: AppTheme.green,
                    duration: const Duration(seconds: 2),
                  ));
                  // Rebuild to show new name
                  (context as Element).markNeedsBuild();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Failed: $e'),
                    backgroundColor: AppTheme.red,
                  ));
                }
              }
            },
            child: const Text('Save',
                style: TextStyle(
                    color: AppTheme.green, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Password dialog ──
  void _showPasswordDialog(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surface2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Change Password',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (errorText != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.redDim,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(errorText!,
                      style: const TextStyle(
                          color: AppTheme.red,
                          fontSize: 11,
                          fontFamily: 'Courier')),
                ),
                const SizedBox(height: 12),
              ],
              _PasswordField(
                  controller: currentCtrl, hint: 'Current password'),
              const SizedBox(height: 10),
              _PasswordField(controller: newCtrl, hint: 'New password'),
              const SizedBox(height: 10),
              _PasswordField(
                  controller: confirmCtrl, hint: 'Confirm new password'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textMuted)),
            ),
            TextButton(
              onPressed: () async {
                final currentPw = currentCtrl.text;
                final newPw = newCtrl.text;
                final confirmPw = confirmCtrl.text;

                if (currentPw.isEmpty || newPw.isEmpty) {
                  setDialogState(
                      () => errorText = 'Please fill in all fields');
                  return;
                }
                if (newPw != confirmPw) {
                  setDialogState(
                      () => errorText = 'New passwords do not match');
                  return;
                }
                if (newPw.length < 6) {
                  setDialogState(() =>
                      errorText = 'Password must be at least 6 characters');
                  return;
                }

                try {
                  final user = FirebaseAuth.instance.currentUser;
                  final cred = EmailAuthProvider.credential(
                    email: user?.email ?? '',
                    password: currentPw,
                  );
                  await user?.reauthenticateWithCredential(cred);
                  await user?.updatePassword(newPw);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Password updated successfully'),
                      backgroundColor: AppTheme.green,
                      duration: Duration(seconds: 2),
                    ));
                  }
                } on FirebaseAuthException catch (e) {
                  setDialogState(
                      () => errorText = e.message ?? 'Authentication failed');
                } catch (e) {
                  setDialogState(() => errorText = '$e');
                }
              },
              child: const Text('Update',
                  style: TextStyle(
                      color: AppTheme.green, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sign out confirmation ──
  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Sign Out',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<app.AuthProvider>().signOut();
            },
            child: const Text('Sign Out',
                style: TextStyle(
                    color: AppTheme.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Section label ──
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 10,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
      );
}

// ── Profile row ──
class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onEdit;
  final bool isLast;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onEdit,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 10,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (onEdit != null)
            GestureDetector(
              onTap: onEdit,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.greenDim,
                  border: Border.all(color: AppTheme.greenBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('EDIT',
                    style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.green)),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Tappable row (for TOS, Privacy, Subscription) ──
class _TappableRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _TappableRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            if (trailing != null) trailing!,
            if (onTap != null)
              const Icon(Icons.chevron_right,
                  size: 20, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Legal content screen ──
class _LegalScreen extends StatelessWidget {
  final String title;
  final String content;
  const _LegalScreen({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios,
                        size: 16, color: AppTheme.green),
                  ),
                  const SizedBox(width: 10),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Text(content,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMuted,
                          height: 1.6)),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Password text field ──
class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _PasswordField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: true,
        style: const TextStyle(
            fontFamily: 'Courier', fontSize: 13, color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          filled: true,
          fillColor: AppTheme.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.green)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
}

// ── Legal text constants ──

const String _kTermsOfService = '''
Terms of Service

Last updated: March 2026

1. Acceptance of Terms
By accessing or using MarketWars ("the App"), you agree to be bound by these Terms of Service. If you do not agree, do not use the App.

2. Description of Service
MarketWars is a fantasy stock trading game for entertainment purposes only. No real money is invested, and no real securities are bought or sold through the App.

3. Eligibility
You must be at least 13 years of age to use the App. By using the App, you represent that you meet this requirement.

4. User Accounts
You are responsible for maintaining the confidentiality of your account credentials. You agree to provide accurate information during registration and to keep your account information up to date.

5. User Conduct
You agree not to:
- Use the App for any unlawful purpose
- Interfere with or disrupt the App or its servers
- Attempt to gain unauthorized access to any part of the App
- Use automated means to access the App without permission
- Harass, abuse, or harm other users

6. Intellectual Property
All content, features, and functionality of the App are owned by MarketWars and are protected by copyright, trademark, and other intellectual property laws.

7. Disclaimer
The App is provided "as is" without warranties of any kind. MarketWars does not guarantee the accuracy of stock data or game results. This is not a financial advisory service.

8. Limitation of Liability
MarketWars shall not be liable for any indirect, incidental, special, or consequential damages arising from your use of the App.

9. Termination
We reserve the right to suspend or terminate your account at any time for violations of these terms or for any other reason at our discretion.

10. Changes to Terms
We may update these terms from time to time. Continued use of the App after changes constitutes acceptance of the new terms.

11. Contact
For questions about these Terms, contact us through the App's support channels.
''';

const String _kPrivacyPolicy = '''
Privacy Policy

Last updated: March 2026

1. Information We Collect
- Account information: username, email address, and password
- Usage data: game activity, league participation, and draft picks
- Device information: device type, operating system, and app version

2. How We Use Your Information
- To provide and maintain the App
- To manage your account and enable game features
- To communicate with you about updates and changes
- To monitor and analyze usage patterns to improve the App

3. Data Storage
Your data is stored securely using Firebase services provided by Google. We implement appropriate security measures to protect your personal information.

4. Information Sharing
We do not sell your personal information. We may share data with:
- Service providers who assist in operating the App (e.g., Firebase)
- Law enforcement when required by law

5. Your Rights
You may:
- Access and update your account information at any time
- Request deletion of your account and associated data
- Opt out of non-essential communications

6. Data Retention
We retain your data for as long as your account is active. Upon account deletion, we will remove your personal data within 30 days.

7. Children's Privacy
The App is not intended for children under 13. We do not knowingly collect data from children under 13.

8. Changes to This Policy
We may update this policy from time to time. We will notify you of significant changes through the App.

9. Contact
For privacy-related questions or requests, contact us through the App's support channels.
''';
