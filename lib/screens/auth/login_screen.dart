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
  bool _obscurePassword = true;
  bool _disclaimerChecked = false;

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
                decoration: InputDecoration(
                  hintText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: AppTheme.textMuted,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
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

              // Disclaimer checkbox (signup only)
              if (_isSignUp) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => setState(() => _disclaimerChecked = !_disclaimerChecked),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: _disclaimerChecked,
                          onChanged: (v) => setState(() => _disclaimerChecked = v ?? false),
                          activeColor: AppTheme.green,
                          side: const BorderSide(color: AppTheme.textMuted),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Market Wars is a fantasy competition game for entertainment '
                          'and educational purposes only. No real securities are bought '
                          'or sold. Nothing in this app constitutes investment advice. '
                          'By continuing, you agree to our Terms of Service and Privacy Policy.',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                            fontFamily: 'Courier',
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Submit button
              ElevatedButton(
                onPressed: (_isSignUp && !_disclaimerChecked)
                    ? null
                    : () {
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
