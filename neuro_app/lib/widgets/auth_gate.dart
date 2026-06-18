import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/login_screen.dart';
import '../services/supabase_bootstrap.dart';
import 'entry_splash.dart';

class AuthGate extends StatefulWidget {
  final Widget child;

  const AuthGate({super.key, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Session? _session;
  StreamSubscription<AuthState>? _authSubscription;
  bool _showEntrySplash = false;

  @override
  void initState() {
    super.initState();

    if (!SupabaseConfig.isConfigured) {
      return;
    }

    final auth = Supabase.instance.client.auth;
    _session = auth.currentSession;
    _authSubscription = auth.onAuthStateChange.listen((event) {
      if (!mounted) {
        return;
      }

      final wasSignedOut = _session == null;
      final isSignedIn = event.session != null;

      setState(() {
        _session = event.session;
        _showEntrySplash = wasSignedOut && isSignedIn;
      });
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isConfigured) {
      return widget.child;
    }

    if (_session == null) {
      return LoginScreen(onSignedIn: _handleSignedIn);
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
      _session = Supabase.instance.client.auth.currentSession;
      _showEntrySplash = _session != null;
    });
  }
}
