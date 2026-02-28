import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? _user;
  bool _isLoading = true;
  String _errorMessage = '';

  bool   get isLoggedIn    => _user != null;
  bool   get isLoading     => _isLoading;
  String get errorMessage  => _errorMessage;
  String get uid           => _user?.uid ?? '';
  String get username      => _user?.displayName ?? 'Player';

  AuthProvider() {
    _auth.authStateChanges().listen((user) {
      _user = user;
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> signUp(String email, String password, String username) async {
    try {
      _errorMessage = '';
      final result = await _auth.createUserWithEmailAndPassword(
        email: email, password: password,
      );
      await result.user?.updateDisplayName(username);
      if (result.user != null) {
        final profile = UserProfile(
          id: result.user!.uid, username: username, email: email,
          cashBalance: UserProfile.startingBalance,
          totalValue: UserProfile.startingBalance,
          createdAt: DateTime.now(),
        );
        await _db.collection('users').doc(result.user!.uid).set(profile.toMap());
      }
    } on FirebaseAuthException catch (e) {
      _errorMessage = e.message ?? 'Sign up failed';
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    try {
      _errorMessage = '';
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      _errorMessage = e.message ?? 'Sign in failed';
      notifyListeners();
    }
  }

  Future<void> signOut() async => await _auth.signOut();

  void clearError() {
    _errorMessage = '';
    notifyListeners();
  }
}
