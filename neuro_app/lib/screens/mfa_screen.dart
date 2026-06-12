import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MfaScreen extends StatefulWidget {
  const MfaScreen({super.key});

  @override
  State<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends State<MfaScreen> {
  final _codeController = TextEditingController();
  Future<_MfaState>? _stateFuture;
  AuthMFAEnrollResponse? _enrollment;
  Factor? _selectedFactor;
  bool _isWorking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _stateFuture = _loadState();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor verification')),
      body: FutureBuilder<_MfaState>(
        future: _stateFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _MfaErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final state = snapshot.data!;

          if (state.isVerified) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.pop(context, true);
              }
            });
            return const Center(child: CircularProgressIndicator());
          }

          if (_enrollment != null) {
            return _buildEnrollmentVerification(_enrollment!);
          }

          if (state.verifiedFactors.isEmpty) {
            return _buildEnrollmentPrompt();
          }

          _selectedFactor ??= state.verifiedFactors.first;
          return _buildExistingFactorVerification(state.verifiedFactors);
        },
      ),
    );
  }

  Future<_MfaState> _loadState() async {
    final auth = Supabase.instance.client.auth;
    final aal = auth.mfa.getAuthenticatorAssuranceLevel();
    final factors = await auth.mfa.listFactors();

    return _MfaState(
      isVerified: aal.currentLevel == AuthenticatorAssuranceLevels.aal2,
      verifiedFactors: factors.totp,
    );
  }

  void _reload() {
    setState(() {
      _stateFuture = _loadState();
      _errorMessage = null;
    });
  }

  Widget _buildEnrollmentPrompt() {
    return _MfaPanel(
      title: 'Set up two-factor verification',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Admin actions require an authenticator code. Set up a TOTP factor '
            'with your authenticator app, then enter the six-digit code.',
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _isWorking ? null : _startEnrollment,
            icon: _isWorking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_2),
            label: const Text('Start setup'),
          ),
          _ErrorText(message: _errorMessage),
        ],
      ),
    );
  }

  Widget _buildEnrollmentVerification(AuthMFAEnrollResponse enrollment) {
    final totp = enrollment.totp;

    return _MfaPanel(
      title: 'Scan and verify',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (totp != null) ...[
            const Text(
              'Open your authenticator app and use its add-account QR scanner. '
              'A normal phone camera may only show the setup text.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Center(
              child: QrImageView(
                data: totp.uri,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              'Secret: ${totp.secret}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
          ],
          _CodeField(
            controller: _codeController,
            onSubmitted: _verifyEnrollment,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _isWorking ? null : _verifyEnrollment,
            icon: _isWorking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_user),
            label: const Text('Verify code'),
          ),
          _ErrorText(message: _errorMessage),
        ],
      ),
    );
  }

  Widget _buildExistingFactorVerification(List<Factor> factors) {
    return _MfaPanel(
      title: 'Enter authenticator code',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (factors.length > 1) ...[
            DropdownButtonFormField<Factor>(
              initialValue: _selectedFactor,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Factor',
              ),
              items: [
                for (final factor in factors)
                  DropdownMenuItem(
                    value: factor,
                    child: Text(factor.friendlyName ?? 'Authenticator'),
                  ),
              ],
              onChanged: (factor) {
                setState(() {
                  _selectedFactor = factor;
                });
              },
            ),
            const SizedBox(height: 12),
          ],
          _CodeField(controller: _codeController, onSubmitted: _verifyFactor),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _isWorking ? null : _verifyFactor,
            icon: _isWorking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_user),
            label: const Text('Verify'),
          ),
          _ErrorText(message: _errorMessage),
        ],
      ),
    );
  }

  Future<void> _startEnrollment() async {
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    try {
      final enrollment = await Supabase.instance.client.auth.mfa.enroll(
        issuer: 'NeuroDienst',
        friendlyName: 'NeuroDienst',
      );

      setState(() {
        _enrollment = enrollment;
      });
    } on AuthException catch (error) {
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Could not start MFA setup.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  Future<void> _verifyEnrollment() async {
    final enrollment = _enrollment;

    if (enrollment == null) {
      return;
    }

    await _verifyFactorId(enrollment.id);
  }

  Future<void> _verifyFactor() async {
    final factor = _selectedFactor;

    if (factor == null) {
      setState(() {
        _errorMessage = 'No MFA factor selected.';
      });
      return;
    }

    await _verifyFactorId(factor.id);
  }

  Future<void> _verifyFactorId(String factorId) async {
    final code = _codeController.text.trim();

    if (code.isEmpty) {
      setState(() {
        _errorMessage = 'Enter the six-digit code.';
      });
      return;
    }

    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    try {
      await Supabase.instance.client.auth.mfa.challengeAndVerify(
        factorId: factorId,
        code: code,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } on AuthException catch (error) {
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Could not verify the MFA code.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }
}

class _MfaState {
  final bool isVerified;
  final List<Factor> verifiedFactors;

  const _MfaState({required this.isVerified, required this.verifiedFactors});
}

class _MfaPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const _MfaPanel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  const _CodeField({required this.controller, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmitted(),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'Verification code',
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String? message;

  const _ErrorText({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        message!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _MfaErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _MfaErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
