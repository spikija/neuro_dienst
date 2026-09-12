import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/login_screen.dart';
import '../screens/password_recovery_screen.dart';
import '../services/supabase_bootstrap.dart';
import 'entry_splash.dart';

class AuthGate extends StatefulWidget {
  final Widget child;
  final GoTrueClient? auth;

  const AuthGate({super.key, required this.child, this.auth});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Session? _session;
  StreamSubscription<AuthState>? _authSubscription;
  bool _showEntrySplash = false;
  bool _isPasswordRecovery = false;
  GoTrueClient? get _auth =>
      widget.auth ??
      (SupabaseConfig.isConfigured ? Supabase.instance.client.auth : null);

  @override
  void initState() {
    super.initState();

    final auth = _auth;
    if (auth == null) {
      return;
    }

    _session = auth.currentSession;
    _showEntrySplash = _session != null;
    _authSubscription = auth.onAuthStateChange.listen(
      (event) {
        if (!mounted) {
          return;
        }

        final wasSignedOut = _session == null;
        final isSignedIn = event.session != null;

        setState(() {
          _session = event.session;
          if (event.event == AuthChangeEvent.passwordRecovery && isSignedIn) {
            _isPasswordRecovery = true;
            _showEntrySplash = false;
            // The request form (or another pushed page) may still cover the gate.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _isPasswordRecovery) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            });
            return;
          }
          if (!isSignedIn) {
            _showEntrySplash = false;
            _isPasswordRecovery = false;
            return;
          }

          if (wasSignedOut) {
            _showEntrySplash = true;
          }
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Authentication could not be completed. Please sign in again or '
              'request a new password-reset link on this device. / '
              'Anmeldung fehlgeschlagen. Bitte erneut anmelden oder auf diesem '
              'Gerät einen neuen Passwort-Link anfordern.',
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_auth == null) {
      return widget.child;
    }

    if (_session == null) {
      return LoginScreen(onSignedIn: _handleSignedIn);
    }

    if (_isPasswordRecovery) {
      return UpdatePasswordScreen(
        auth: _auth,
        onCompleted: _finishPasswordRecovery,
      );
    }

    if (_showEntrySplash) {
      return EntrySplash(
        onFinished: () {
          if (!mounted) {
            return;
          }

          setState(() {
            _showEntrySplash = false;
          });
        },
      );
    }

    return widget.child;
  }

  void _handleSignedIn() {
    if (!mounted) {
      return;
    }

    setState(() {
      _session = _auth?.currentSession;
      _showEntrySplash = _session != null;
    });
  }

  Future<void> _finishPasswordRecovery() async {
    await _auth?.signOut();
    if (!mounted) {
      return;
    }

    setState(() {
      _session = null;
      _isPasswordRecovery = false;
      _showEntrySplash = false;
    });
  }
}
