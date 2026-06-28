import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/feedback_sound_service.dart';
import '../widgets/entry_splash.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onSignedIn;

  const LoginScreen({super.key, this.onSignedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _internalEmailDomain = 'neurodienst.local';
  static const _supportEmail = 'spikija@gmail.com';

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'NeuroDienst',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sign in to continue / Anmelden zum Fortfahren',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
                const SizedBox(height: 12),
                Text(
                  'Plan neurology duty rosters, absences, and monthly '
                  'coverage in one shared workspace.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Neurologische Dienstplaene, Abwesenheiten und '
                  'Monatsabdeckung gemeinsam planen.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _usernameController,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Username / Benutzername',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _signIn(),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'Password / Passwort',
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Show password / Passwort anzeigen'
                          : 'Hide password / Passwort verbergen',
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _signIn,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const Text('Sign in / Anmelden'),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _openSupportEmail,
                  icon: const Icon(Icons.mail_outline),
                  label: Text(
                    'Support and feedback / Support und Feedback: '
                    '$_supportEmail',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _loginEmailFromUsername(_usernameController.text),
        password: _passwordController.text,
      );
      await FeedbackSoundService.playLogin();

      if (mounted) {
        await _showEntrySplash();
      }

      widget.onSignedIn?.call();
    } on AuthException catch (error) {
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      setState(() {
        _errorMessage =
            'Sign in failed. Please try again. / '
            'Anmeldung fehlgeschlagen. Bitte erneut versuchen.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openSupportEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: const {'subject': 'NeuroDienst feedback'},
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _loginEmailFromUsername(String value) {
    final trimmed = value.trim().toLowerCase();

    if (trimmed.contains('@')) {
      return trimmed;
    }

    return '$trimmed@$_internalEmailDomain';
  }

  Future<void> _showEntrySplash() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return EntrySplash(
            onFinished: () {
              Navigator.of(context).pop();
            },
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}
