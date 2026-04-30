import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../settings/presentation/bloc/settings_bloc.dart';
import '../../../settings/presentation/bloc/settings_event.dart';
import '../../../settings/presentation/bloc/settings_state.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingContent> _contents = [
    OnboardingContent(
      title: 'Welcome to CodeNote',
      description: 'The professional, developer-centric productivity suite for your code snippets and notes.',
      image: 'assets/onboarding/workspace.png',
    ),
    OnboardingContent(
      title: 'Powerful Code Editor',
      description: 'Write, edit and organize your code blocks with full syntax highlighting for over 20 languages.',
      image: 'assets/onboarding/typing.png',
    ),
    OnboardingContent(
      title: 'Share & Export',
      description: 'Share your snippets as files or copy them to your clipboard with a single tap.',
      image: 'assets/onboarding/share.png',
    ),
    OnboardingContent(
      title: '100% Privacy',
      description: 'This is the Community Edition. Your data is stored strictly on your device. No cloud, no tracking.',
      image: 'assets/onboarding/sync.png', // Using sync.png but with privacy message
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _contents.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          _contents[index].image,
                          height: 300,
                        ).animate().fade(duration: 500.ms).scale(delay: 100.ms),
                        const SizedBox(height: 40),
                        Text(
                          _contents[index].title,
                          textAlign: TextAlign.center,
                          style: text.headlineMedium!.copyWith(
                            fontWeight: FontWeight.bold,
                            color: color.primary,
                          ),
                        ).animate().slideY(begin: 0.2, end: 0, duration: 500.ms).fade(),
                        const SizedBox(height: 20),
                        Text(
                          _contents[index].description,
                          textAlign: TextAlign.center,
                          style: text.bodyLarge!.copyWith(
                            color: color.onSurfaceVariant,
                          ),
                        ).animate().slideY(begin: 0.3, end: 0, delay: 100.ms, duration: 500.ms).fade(),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(
                      _contents.length,
                      (index) => Container(
                        margin: const EdgeInsets.only(right: 8),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index ? color.primary : color.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  BlocBuilder<SettingsBloc, SettingsState>(
                    builder: (context, state) {
                      return ElevatedButton(
                        onPressed: () {
                          if (_currentPage == _contents.length - 1) {
                            if (state is SettingsLoaded) {
                              final updatedSettings = state.settings.copyWith(
                                hasCompletedOnboarding: true,
                              );
                              context.read<SettingsBloc>().add(UpdateSettingsEvent(updatedSettings));
                            }
                          } else {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _currentPage == _contents.length - 1 ? 'Get Started' : 'Next',
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingContent {
  final String title;
  final String description;
  final String image;

  OnboardingContent({
    required this.title,
    required this.description,
    required this.image,
  });
}
