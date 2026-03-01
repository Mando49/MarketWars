import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  bool _isSignUp = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              // Logo
              Column(
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    height: 200,
                    width: 200,
                  ),
                  const SizedBox(height: 8),
                  const Text('Market Wars',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.green,
                          letterSpacing: -1)),
                  const SizedBox(height: 4),
                  const Text('Compete with real stocks',
                      style:
                          TextStyle(color: AppTheme.textMuted, fontSize: 14)),
                ],
              ), // Column

              const SizedBox(height: 48),

              // Fields
              if (_isSignUp) ...[
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(hintText: 'Username'),
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(hintText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                decoration: const InputDecoration(hintText: 'Password'),
                obscureText: true,
                style: const TextStyle(color: AppTheme.textPrimary),
              ),

              // Error
              if (auth.errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  auth.errorMessage,
                  style: const TextStyle(color: AppTheme.red, fontSize: 13),
                ),
              ],

              const SizedBox(height: 20),

              // Submit button
              ElevatedButton(
                onPressed: () {
                  if (_isSignUp) {
                    auth.signUp(
                      _emailCtrl.text.trim(),
                      _passwordCtrl.text,
                      _usernameCtrl.text.trim(),
                    );
                  } else {
                    auth.signIn(_emailCtrl.text.trim(), _passwordCtrl.text);
                  }
                },
                child: Text(_isSignUp ? 'Create Account' : 'Sign In'),
              ),

              const SizedBox(height: 16),

              // Toggle
              TextButton(
                onPressed: () {
                  auth.clearError();
                  setState(() => _isSignUp = !_isSignUp);
                },
                child: Text(
                  _isSignUp
                      ? 'Already have an account? Sign In'
                      : "New here? Create Account",
                  style: const TextStyle(color: AppTheme.green),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }
}
