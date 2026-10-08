import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/roster_reader.dart';
import '../roster_dashboard.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart'
    show AssignmentMutationService;

enum AccessLevel { denied, requiresMfa, ready }

class AccessCheck {
  final AccessLevel level;
  final List<(String, String)> factors;
  const AccessCheck(this.level, {this.factors = const []});
}

abstract interface class SessionGateway {
  bool get isSignedIn;
  Stream<void> get changes;
  Future<AccessCheck> checkAccess();
  Future<void> signIn(String email, String password);
  Future<void> verify(String factorId, String code);
  Future<void> signOut();
}

class SupabaseSessionGateway implements SessionGateway {
  final SupabaseClient client;
  SupabaseSessionGateway(this.client);

  @override
  bool get isSignedIn => client.auth.currentSession != null;
  @override
  Stream<void> get changes => client.auth.onAuthStateChange.map((_) {});

  @override
  Future<AccessCheck> checkAccess() async {
    // Validate the persisted token with Auth, rather than trusting local claims.
    final user = (await client.auth.getUser()).user;
    if (user == null) return const AccessCheck(AccessLevel.denied);
    final profile = await client
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    if (profile?['role'] != 'admin') {
      return const AccessCheck(AccessLevel.denied);
    }
    final assurance = client.auth.mfa.getAuthenticatorAssuranceLevel();
    if (assurance.currentLevel == AuthenticatorAssuranceLevels.aal2) {
      return const AccessCheck(AccessLevel.ready);
    }
    // listFactors() refreshes the session in the installed SDK. Calling it
    // from a tokenRefreshed listener creates an auth-event/refresh loop.
    // getUser() above already returns the server-verified enrolled factors.
    return AccessCheck(
      AccessLevel.requiresMfa,
      factors: [
        for (final factor in (user.factors ?? []).where(
          (factor) =>
              factor.factorType == FactorType.totp &&
              factor.status == FactorStatus.verified,
        ))
          (factor.id, factor.friendlyName ?? 'Authenticator'),
      ],
    );
  }

  @override
  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> verify(String factorId, String code) async {
    await client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  @override
  Future<void> signOut() => client.auth.signOut();
}

class SessionGate extends StatefulWidget {
  final AssignmentMutationService? mutations;
  final SessionGateway gateway;
  final RosterReader reader;
  const SessionGate({
    super.key,
    required this.gateway,
    required this.reader,
    this.mutations,
  });

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  StreamSubscription<void>? _subscription;
  Future<AccessCheck>? _check;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _passwordVisible = false;
  String? _error;
  String? _factorId;

  @override
  void initState() {
    super.initState();
    _reload();
    _subscription = widget.gateway.changes.listen(
      (_) {
        if (mounted) setState(_reload);
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _check = null;
            _error = 'Session verification failed. Sign out and try again.';
          });
        }
      },
    );
  }

  void _reload() {
    _check = widget.gateway.isSignedIn ? widget.gateway.checkAccess() : null;
    _factorId = null;
    _code.clear();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      if (mounted) setState(_reload);
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not complete authentication. Please retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _signIn() => _perform(() async {
    final password = _password.text;
    _password.clear();
    await widget.gateway.signIn(_email.text.trim(), password);
  });

  @override
  Widget build(BuildContext context) {
    if (!widget.gateway.isSignedIn) {
      return _panel([
        Text(
          'Administrator sign-in',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
          autofillHints: const [AutofillHints.username],
        ),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: !_passwordVisible,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Password',
            suffixIcon: IconButton(
              tooltip: _passwordVisible ? 'Hide password' : 'Show password',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _passwordVisible = !_passwordVisible;
                    }),
              icon: Icon(
                _passwordVisible ? Icons.visibility_off : Icons.visibility,
              ),
            ),
          ),
          onSubmitted: (_) => _signIn(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: const Text('Sign in'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Use your existing NeuroDienst administrator account. Password recovery and MFA enrollment are available in the existing app.',
        ),
      ]);
    }
    if (_check == null) {
      return _panel([const Text('Session verification unavailable.')]);
    }
    return FutureBuilder<AccessCheck>(
      future: _check,
      builder: (context, snapshot) {
        // Never keep displaying old roster data while credentials are rechecked.
        if (snapshot.connectionState != ConnectionState.done) {
          return _panel([const Center(child: CircularProgressIndicator())]);
        }
        if (snapshot.hasError) {
          return _panel([
            const Text('Could not verify administrator access.'),
            TextButton(
              onPressed: () => setState(_reload),
              child: const Text('Retry'),
            ),
          ]);
        }
        final access = snapshot.requireData;
        if (access.level == AccessLevel.denied) {
          return _panel([
            const Text(
              'Administrator access required. This desktop client is not available to doctor or viewer accounts.',
            ),
          ]);
        }
        if (access.level == AccessLevel.ready) {
          return RosterDashboard(
            reader: widget.reader,
            onSignOut: widget.gateway.signOut,
            mutations: widget.mutations,
          );
        }
        if (access.factors.isEmpty) {
          return _panel([
            const Text(
              'Set up an authenticator in the existing NeuroDienst app, then retry.',
            ),
            TextButton(
              onPressed: () => setState(_reload),
              child: const Text('Retry'),
            ),
          ]);
        }
        final selected = access.factors.any((factor) => factor.$1 == _factorId)
            ? _factorId!
            : access.factors.first.$1;
        return _panel([
          Text(
            'Two-factor verification',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          DropdownButton<String>(
            value: selected,
            isExpanded: true,
            items: [
              for (final factor in access.factors)
                DropdownMenuItem(value: factor.$1, child: Text(factor.$2)),
            ],
            onChanged: _busy
                ? null
                : (id) => setState(() {
                    _factorId = id;
                  }),
          ),
          TextField(
            controller: _code,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Authenticator code'),
            onSubmitted: (_) => _verify(selected),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _verify(selected),
            child: const Text('Verify'),
          ),
        ]);
      },
    );
  }

  Future<void> _verify(String factorId) async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _error = 'Enter a six-digit authenticator code.';
      });
      return;
    }
    await _perform(() => widget.gateway.verify(factorId, code));
  }

  Widget _panel(List<Widget> children) => Scaffold(
    appBar: AppBar(
      title: const Text('NeuroDienst Admin'),
      actions: [
        if (widget.gateway.isSignedIn)
          TextButton(
            onPressed: _busy ? null : () => _perform(widget.gateway.signOut),
            child: const Text('Sign out'),
          ),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...children,
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
