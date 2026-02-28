import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/auth_client.dart';
import '../../core/toast_provider.dart';
import '../../main.dart' show authClientProvider;

const _rememberEmailKey = 'trinity_remember_email';
const _savedEmailKey = 'trinity_saved_email';

class LoginPage extends ConsumerStatefulWidget {
  final VoidCallback? onLoginSuccess;

  const LoginPage({super.key, this.onLoginSuccess});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true; // true=login, false=signup
  bool _loading = false;
  bool _rememberEmail = false;

  @override
  void initState() {
    super.initState();
    final stored = html.window.localStorage[_rememberEmailKey];
    if (stored == 'true') {
      _rememberEmail = true;
      final savedEmail = html.window.localStorage[_savedEmailKey] ?? '';
      _emailController.text = savedEmail;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() => _loading = true);

    try {
      final authClient = ref.read(authClientProvider);
      if (_isLogin) {
        await authClient.loginWithEmail(email, password);
      } else {
        await authClient.signUpWithEmail(email, password);
      }

      // Persist or clear remembered email
      if (_rememberEmail) {
        html.window.localStorage[_savedEmailKey] = email;
        html.window.localStorage[_rememberEmailKey] = 'true';
      } else {
        html.window.localStorage.remove(_savedEmailKey);
        html.window.localStorage.remove(_rememberEmailKey);
      }

      widget.onLoginSuccess?.call();
    } catch (e) {
      final errMsg = e.toString().replaceAll('Exception: ', '');
      ToastService.showError(context, errMsg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginAsGuest() async {
    setState(() {
      _loading = true;
    });

    try {
      final authClient = ref.read(authClientProvider);
      await authClient.loginAsGuest();
      widget.onLoginSuccess?.call();
    } catch (e) {
      final errMsg = e.toString().replaceAll('Exception: ', '');
      ToastService.showError(context, errMsg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: t.surfaceBase,
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'trinity',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: t.accentPrimary,
                ),
              ),
              const SizedBox(height: 24),
              // Email
              TextField(
                controller: _emailController,
                autofocus: !_rememberEmail,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'email',
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: t.border),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: t.accentPrimary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Password
              TextField(
                controller: _passwordController,
                autofocus: _rememberEmail,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'password',
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: t.border),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: t.accentPrimary),
                  ),
                ),
                onSubmitted: (_) => _submitEmail(),
              ),
              const SizedBox(height: 12),
              // Remember email
              GestureDetector(
                onTap: () => setState(() => _rememberEmail = !_rememberEmail),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _rememberEmail ? t.accentPrimary : Colors.transparent,
                        border: Border.all(
                          color: _rememberEmail ? t.accentPrimary : t.border,
                          width: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'remember email',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: t.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Actions
              Row(
                children: [
                  GestureDetector(
                    onTap: _loading ? null : _submitEmail,
                    child: Text(
                      _isLogin ? 'login' : 'sign up',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _loading ? t.fgDisabled : t.accentPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => setState(() => _isLogin = !_isLogin),
                    child: Text(
                      _isLogin ? 'create account' : 'have an account',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: t.fgMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Divider(color: t.border, thickness: 0.5),
              const SizedBox(height: 16),
              // SSO
              GestureDetector(
                onTap: _loading
                    ? null
                    : () {
                        final authClient = ref.read(authClientProvider);
                        final url = authClient.getKeycloakLoginUrl();
                        debugPrint('SSO URL: $url (not yet implemented)');
                      },
                child: Tooltip(
                  message: 'SSO integration coming soon',
                  child: Text(
                    'sign in with SSO',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: t.fgDisabled,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Guest
              GestureDetector(
                onTap: _loading ? null : _loginAsGuest,
                child: Text(
                  'continue as guest',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: t.fgTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
