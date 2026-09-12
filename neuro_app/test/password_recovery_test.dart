import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_app/screens/login_screen.dart';
import 'package:neuro_app/screens/password_recovery_screen.dart';
import 'package:neuro_app/widgets/auth_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeRecoveryAuth extends GoTrueClient {
  final events = StreamController<AuthState>.broadcast();
  Session? session;
  AuthState? initialEvent;
  String? requestedEmail;
  String? requestedRedirect;
  String? updatedPassword;
  int resetRequests = 0;
  bool signedOut = false;
  Completer<void>? pendingRequest;
  AuthException? requestError;

  FakeRecoveryAuth() : super(autoRefreshToken: false);

  @override
  Session? get currentSession => session;

  @override
  Stream<AuthState> get onAuthStateChange async* {
    if (initialEvent != null) yield initialEvent!;
    yield* events.stream;
  }

  @override
  Future<void> resetPasswordForEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) async {
    resetRequests++;
    requestedEmail = email;
    requestedRedirect = redirectTo;
    if (requestError != null) throw requestError!;
    await pendingRequest?.future;
  }

  @override
  Future<UserResponse> updateUser(
    UserAttributes attributes, {
    String? emailRedirectTo,
  }) async {
    updatedPassword = attributes.password;
    return UserResponse.fromJson(session?.user.toJson() ?? {});
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    signedOut = true;
    session = null;
    events.add(AuthState(AuthChangeEvent.signedOut, null));
  }

  @override
  void dispose() {
    events.close();
    super.dispose();
  }
}

Session recoverySession() => Session(
  accessToken: 'test-token',
  tokenType: 'bearer',
  user: User(
    id: 'test-user',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-06-01T00:00:00Z',
  ),
);

void main() {
  late FakeRecoveryAuth auth;
  setUp(() => auth = FakeRecoveryAuth());
  tearDown(() => auth.dispose());

  testWidgets(
    'request uses the exact allowed redirect, normalizes email and prevents duplicate submissions',
    (tester) async {
      auth.pendingRequest = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(home: ForgotPasswordScreen(auth: auth)),
      );
      await tester.enterText(find.byType(TextField), ' Person@Example.com ');
      await tester.tap(find.text('Send reset link / Link senden'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(auth.resetRequests, 1);
      expect(auth.requestedEmail, 'person@example.com');
      expect(
        auth.requestedRedirect,
        'io.neurodienst.app://auth/reset-password',
      );
      auth.pendingRequest!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('If an account exists'), findsOneWidget);
    },
  );

  testWidgets(
    'invalid email never sends a reset request and request errors allow retry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ForgotPasswordScreen(auth: auth)),
      );
      await tester.enterText(find.byType(TextField), 'invalid');
      await tester.tap(find.text('Send reset link / Link senden'));
      await tester.pumpAndSettle();
      expect(auth.resetRequests, 0);
      auth.requestError = const AuthException('Email rate limit exceeded');
      await tester.enterText(find.byType(TextField), 'person@example.com');
      await tester.tap(find.text('Send reset link / Link senden'));
      await tester.pumpAndSettle();
      expect(find.text('Email rate limit exceeded'), findsOneWidget);
      auth.requestError = null;
      await tester.tap(find.text('Send reset link / Link senden'));
      await tester.pumpAndSettle();
      expect(find.textContaining('If an account exists'), findsOneWidget);
    },
  );

  testWidgets(
    'recovery returns above the request route and saves the new password then signs out',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            auth: auth,
            child: const Scaffold(body: Text('Roster')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password? / Passwort vergessen?'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      auth.session = recoverySession();
      auth.events.add(
        AuthState(AuthChangeEvent.passwordRecovery, auth.session),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UpdatePasswordScreen), findsOneWidget);
      expect(find.byType(ForgotPasswordScreen), findsNothing);
      expect(find.text('Roster'), findsNothing);

      // A token refresh must not dismiss password recovery.
      auth.events.add(AuthState(AuthChangeEvent.tokenRefreshed, auth.session));
      await tester.pumpAndSettle();
      expect(find.byType(UpdatePasswordScreen), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        'a-new-password-123',
      );
      await tester.enterText(find.byType(TextField).last, 'a-new-password-123');
      await tester.tap(find.text('Set password / Passwort festlegen'));
      await tester.pumpAndSettle();
      expect(auth.updatedPassword, 'a-new-password-123');
      expect(auth.signedOut, isTrue);
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );

  testWidgets(
    'replayed recovery at startup opens the password form and cancellation signs out',
    (tester) async {
      auth.session = recoverySession();
      auth.initialEvent = AuthState(
        AuthChangeEvent.passwordRecovery,
        auth.session,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            auth: auth,
            child: const Scaffold(body: Text('Roster')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UpdatePasswordScreen), findsOneWidget);
      await tester.tap(find.text('Cancel / Abbrechen'));
      await tester.pumpAndSettle();
      expect(auth.signedOut, isTrue);
      expect(auth.updatedPassword, isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );

  testWidgets(
    'authentication link errors are handled and tell the user how to retry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            auth: auth,
            child: const Scaffold(body: Text('Roster')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      auth.events.addError(const AuthException('Link expired'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('request a new password-reset link'),
        findsOneWidget,
      );
      expect(find.byType(UpdatePasswordScreen), findsNothing);
    },
  );

  testWidgets(
    'password validation prevents short or mismatched passwords on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: UpdatePasswordScreen(auth: auth, onCompleted: () async {}),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'short');
      await tester.enterText(find.byType(TextField).last, 'short');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Use at least 12 characters. /'),
        findsOneWidget,
      );
      expect(auth.updatedPassword, isNull);
      await tester.enterText(
        find.byType(TextField).first,
        'a-new-password-123',
      );
      await tester.enterText(find.byType(TextField).last, 'different-password');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The passwords do not match.'),
        findsOneWidget,
      );
      expect(auth.updatedPassword, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
