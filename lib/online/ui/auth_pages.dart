import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../constants/themes.dart';
import '../../widgets/brand.dart';
import '../backend/backend.dart';
import '../online_config.dart';
import '../online_service.dart';
import 'common.dart';

/// The frame of every sign-in screen: brand on top, a centered card.
/// Email codes: 6 digits from our own server; Supabase can be set to send
/// 6 to 10 (new projects send 8).
const codeMaxLength = 10;

class _AuthFrame extends StatelessWidget {
  const _AuthFrame({required this.title, required this.subtitle, required this.children, this.onBack});
  final String title;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: onBack == null
          ? null
          : AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack), backgroundColor: Colors.transparent),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandMark(size: 56)),
                  const SizedBox(height: 18),
                  Text(title, textAlign: TextAlign.center, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: color.onSurfaceVariant, height: 1.4)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: color.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppBrand.radius),
                      border: Border.all(color: color.outlineVariant.withAlpha(160)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);
  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.errorContainer.withAlpha(140), borderRadius: BorderRadius.circular(AppBrand.radiusSmall)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: 18, color: color.onErrorContainer),
        const SizedBox(width: 10),
        Expanded(child: Text(text!, style: TextStyle(color: color.onErrorContainer, height: 1.35))),
      ]),
    );
  }
}

class _BusyButton extends StatelessWidget {
  const _BusyButton({required this.label, required this.busy, required this.onPressed, this.icon});
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: busy ? null : onPressed,
          icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon ?? Icons.arrow_forward_rounded),
          label: Text(label),
        ),
      );
}

// ─── FastAPI: server address ─────────────────────────────

/// The FastAPI build's first screen: which CodeNote server to use.
class ServerAddressPage extends StatefulWidget {
  const ServerAddressPage({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  State<ServerAddressPage> createState() => _ServerAddressPageState();
}

class _ServerAddressPageState extends State<ServerAddressPage> {
  late final _url = TextEditingController(
      text: OnlineService.instance.serverUrl ?? (OnlineConfig.suggestedServer.isNotEmpty ? OnlineConfig.suggestedServer : ''));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_url.text.trim().isEmpty) {
      setState(() => _error = 'Type the address of your CodeNote server.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await OnlineService.instance.setServer(_url.text);
      if (mounted && widget.onBack != null) Navigator.of(context).maybePop();
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = "That address doesn't work: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return _AuthFrame(
      onBack: widget.onBack,
      title: 'Connect to your server',
      subtitle: 'CodeNote Online keeps your chats and synced notes on a CodeNote server. Type its address to start.',
      children: [
        _ErrorLine(_error),
        TextField(
          controller: _url,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _connect(),
          decoration: const InputDecoration(
            labelText: 'Server address',
            hintText: 'https://chat.example.com',
            prefixIcon: Icon(Icons.dns_outlined),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'On your own computer or network it looks like http://192.168.1.20:8000. '
          'The person who runs the server can tell you the address.',
          style: TextStyle(color: tokens.subtle, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 18),
        _BusyButton(label: 'Connect', busy: _busy, onPressed: _connect, icon: Icons.link_rounded),
        if (widget.onBack == null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => OnlineService.instance.skipForNow(),
            child: const Text('Use CodeNote without an account for now'),
          ),
        ],
      ],
    );
  }
}

// ─── Sign in / create account ────────────────────────────

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.startWithSignUp = false});
  final bool startWithSignUp;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  late bool _signUp = widget.startWithSignUp;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _username = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  bool? _usernameFree;
  Timer? _usernameTimer;
  bool _signupOpen = true;
  String _maintenance = '';

  OnlineService get _online => OnlineService.instance;

  @override
  void initState() {
    super.initState();
    _error = _online.takeSignedOutReason();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    if (!_online.hasBackend) return;
    try {
      final c = await _online.backend.config();
      if (mounted) {
        setState(() {
          _signupOpen = c.signupEnabled;
          _maintenance = c.maintenanceMessage;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _usernameTimer?.cancel();
    for (final c in [_email, _password, _name, _username]) {
      c.dispose();
    }
    super.dispose();
  }

  void _usernameChanged(String v) {
    _usernameTimer?.cancel();
    setState(() => _usernameFree = null);
    final u = v.trim().toLowerCase().replaceFirst('@', '');
    if (!RegExp(r'^[a-z0-9_.]{3,24}$').hasMatch(u)) return;
    _usernameTimer = Timer(const Duration(milliseconds: 450), () async {
      try {
        final free = await _online.backend.usernameAvailable(u);
        if (mounted && _username.text.trim().toLowerCase().replaceFirst('@', '') == u) setState(() => _usernameFree = free);
      } catch (_) {}
    });
  }

  String? _check() {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return "That email address doesn't look right.";
    if (_password.text.length < 8) return 'Passwords need at least 8 characters.';
    if (_signUp) {
      if (_name.text.trim().isEmpty) return 'Type your name.';
      if (!RegExp(r'^[a-z0-9_.]{3,24}$').hasMatch(_username.text.trim().toLowerCase().replaceFirst('@', ''))) {
        return 'Usernames are 3 to 24 characters: letters, numbers, _ and .';
      }
      if (_usernameFree == false) return 'That username is taken. Try another one.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _check();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final b = _online.backend;
      final r = _signUp
          ? await b.signUp(
              email: _email.text.trim(),
              password: _password.text,
              name: _name.text.trim(),
              username: _username.text.trim().toLowerCase().replaceFirst('@', ''))
          : await b.signIn(_email.text.trim(), _password.text);
      await _online.handleAuth(r);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static bool get _googleAvailable =>
      OnlineConfig.googleConfigured && !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool _googleReady = false;

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final g = GoogleSignIn.instance;
      if (!_googleReady) {
        await g.initialize(
          clientId: Platform.isIOS && OnlineConfig.googleIosClientId.isNotEmpty ? OnlineConfig.googleIosClientId : null,
          serverClientId: OnlineConfig.googleWebClientId,
        );
        _googleReady = true;
      }
      final account = await g.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const ApiError("Google didn't give a sign-in token. Try again.");
      await _online.handleAuth(await _online.backend.signInWithGoogle(idToken: idToken));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      final text = '$e'.toLowerCase();
      if (mounted && !text.contains('cancel')) setState(() => _error = "Google sign-in didn't work: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final server = OnlineConfig.isFastApi ? _online.serverName : null;
    return _AuthFrame(
      title: _signUp ? 'Create your account' : 'Welcome back',
      subtitle: _signUp
          ? 'Chat with other developers, send notes and code, and keep your notes on all your devices.'
          : 'Sign in to see your chats and sync your notes.',
      children: [
        if (_maintenance.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: tokens.pin.withAlpha(36), borderRadius: BorderRadius.circular(AppBrand.radiusSmall)),
            child: Row(children: [
              Icon(Icons.construction_rounded, size: 18, color: tokens.pin),
              const SizedBox(width: 10),
              Expanded(child: Text(_maintenance)),
            ]),
          ),
        ],
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Sign in')),
            ButtonSegment(value: true, label: Text('Create account')),
          ],
          selected: {_signUp},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() {
            _signUp = v.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 18),
        _ErrorLine(_error),
        if (_signUp && !_signupOpen)
          const _ErrorLine('Sign-up is closed right now. If you already have an account, sign in.'),
        if (_signUp) ...[
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onChanged: _usernameChanged,
            decoration: InputDecoration(
              labelText: 'Username',
              prefixText: '@',
              prefixIcon: const Icon(Icons.alternate_email_rounded),
              helperText: 'How people find you. Letters, numbers, _ and .',
              suffixIcon: _usernameFree == null
                  ? null
                  : Icon(_usernameFree! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: _usernameFree! ? tokens.success : color.error),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: _signUp ? 'At least 8 characters' : null,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
        ),
        if (!_signUp)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ResetPasswordPage(email: _email.text.trim()))),
              child: const Text('Forgot password?'),
            ),
          )
        else
          const SizedBox(height: 16),
        _BusyButton(label: _signUp ? 'Create account' : 'Sign in', busy: _busy, onPressed: _submit),
        if (_googleAvailable) ...[
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('or', style: TextStyle(color: tokens.subtle))),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _google,
              icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              label: const Text('Continue with Google'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (server != null)
          Center(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Icon(Icons.dns_outlined, size: 14, color: tokens.subtle),
                Text(server, style: monoStyle(context, size: 11.5, color: tokens.subtle)),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.push(context, MaterialPageRoute(builder: (c) => ServerAddressPage(onBack: () => Navigator.pop(c)))),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: _busy ? null : () => _online.skipForNow(),
          child: const Text('Use CodeNote without an account for now'),
        ),
      ],
    );
  }
}

// ─── Email code ──────────────────────────────────────────

class EmailCodePage extends StatefulWidget {
  const EmailCodePage({super.key});

  @override
  State<EmailCodePage> createState() => _EmailCodePageState();
}

class _EmailCodePageState extends State<EmailCodePage> {
  final _code = TextEditingController();
  int _typed = 0; // length of the code before the last change
  bool _busy = false;
  String? _error;
  int _wait = 0;
  Timer? _timer;

  String get _email => OnlineService.instance.pendingEmail ?? '';

  @override
  void initState() {
    super.initState();
    _startWait();
  }

  void _startWait() {
    _wait = 45;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait = _wait > 0 ? _wait - 1 : 0);
      if (_wait == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'The code has 6 numbers.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await OnlineService.instance.verifyEmail(code);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final ok = await attempt(context, () => OnlineService.instance.backend.sendVerification(_email), done: 'A new code is on its way.');
    if (ok && mounted) setState(_startWait);
  }

  @override
  Widget build(BuildContext context) {
    return _AuthFrame(
      onBack: () => OnlineService.instance.signOut(),
      title: 'Check your email',
      subtitle: 'We sent a code to $_email. Type it here to confirm your email.',
      children: [
        _ErrorLine(_error),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: codeMaxLength,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: monoStyle(context, size: 26, weight: FontWeight.w700).copyWith(letterSpacing: 8),
          onChanged: (v) {
            final n = v.trim().length;
            // Supabase can be set to send 6 to 10 digits, so only confirm by
            // itself when the whole code was pasted in one go, or when the
            // own server's 6 digits are complete.
            final pasted = n - _typed > 1 && n >= 6;
            final complete = !OnlineConfig.isSupabase && n == 6;
            _typed = n;
            if (pasted || complete) _verify();
          },
          onSubmitted: (_) => _verify(),
          decoration: const InputDecoration(counterText: '', hintText: 'code'),
        ),
        const SizedBox(height: 16),
        _BusyButton(label: 'Confirm', busy: _busy, onPressed: _verify, icon: Icons.verified_outlined),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _wait > 0 || _busy ? null : _resend,
          child: Text(_wait > 0 ? 'Send a new code in $_wait s' : 'Send a new code'),
        ),
      ],
    );
  }
}

// ─── Password reset ──────────────────────────────────────

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, this.email = ''});
  final String email;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_email.text.contains('@')) {
      setState(() => _error = "That email address doesn't look right.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await OnlineService.instance.backend.sendPasswordReset(_email.text.trim());
      setState(() => _sent = true);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Passwords need at least 8 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await OnlineService.instance.backend.resetPassword(_email.text.trim(), _code.text.trim(), _password.text);
      if (!mounted) return;
      showSnack(context, 'Password changed. Sign in with the new one.');
      Navigator.pop(context);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthFrame(
      onBack: () => Navigator.pop(context),
      title: 'Reset your password',
      subtitle: _sent
          ? 'If there\'s an account for ${_email.text.trim()}, a code is on its way. Type it with your new password.'
          : "Type your account's email. We'll send you a code to set a new password.",
      children: [
        _ErrorLine(_error),
        TextField(
          controller: _email,
          enabled: !_sent,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
        ),
        if (_sent) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: codeMaxLength,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Code', counterText: '', prefixIcon: Icon(Icons.pin_outlined)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters', prefixIcon: Icon(Icons.lock_outline_rounded)),
          ),
        ],
        const SizedBox(height: 18),
        _BusyButton(label: _sent ? 'Set new password' : 'Send code', busy: _busy, onPressed: _sent ? _reset : _send),
        if (_sent) TextButton(onPressed: _busy ? null : _send, child: const Text('Send the code again')),
      ],
    );
  }
}
