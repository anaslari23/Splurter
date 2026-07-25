import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:continuity_state/continuity_state.dart';

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.devices_other_rounded,
                    size: 80,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Splurter',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Android ↔ Mac Continuity',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'Sign in with the same Google account on both your Mac and Android to instantly pair them.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  auth.isLoading
                      ? const CircularProgressIndicator()
                      : Column(
                          children: [
                            FilledButton.icon(
                              onPressed: auth.hasError
                                  ? null
                                  : () => ref.read(authNotifierProvider.notifier).signInWithGoogle(),
                              icon: const Icon(Icons.login),
                              label: const Text('Continue with Google'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                                textStyle: theme.textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: auth.hasError
                                  ? null
                                  : () => ref.read(authNotifierProvider.notifier).signInAnonymously(),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Continue without Google Sign-in'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                                textStyle: theme.textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                  if (auth.hasError) ...[
                    const SizedBox(height: 16),
                    Text(
                      '${auth.error}',
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
