import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../features/settings/presentation/bloc/settings_bloc.dart';
import '../features/settings/presentation/bloc/settings_state.dart';
import '../features/settings/presentation/pages/settings_page.dart';

class UserHomePadge extends StatelessWidget {
  const UserHomePadge({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;

    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        String name = 'User Name';
        String handle = '@username';
        String? profilePath;

        if (state is SettingsLoaded) {
          name = state.settings.userName;
          handle = state.settings.userHandle;
          profilePath = state.settings.profileImagePath;
        }

        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const SettingsPage()),
          ),
          borderRadius: BorderRadius.circular(120),
          child: Container(
            constraints: BoxConstraints(minHeight: size.height * 0.06),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(120),
                color: color.primary.withAlpha(40),
                border: Border.all(color: color.primary.withAlpha(100))),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Hero(
                  tag: 'user_profile_photo',
                  child: CircleAvatar(
                    radius: size.height * 0.025,
                    backgroundColor: color.primaryContainer,
                    backgroundImage: profilePath != null
                        ? (kIsWeb 
                            ? NetworkImage(profilePath) 
                            : FileImage(File(profilePath))) as ImageProvider
                        : const AssetImage('assets/stocks/profile.jpg'),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: text.bodyLarge!.copyWith(
                            color: color.onSurface, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        handle,
                        style: text.bodySmall!.copyWith(color: color.onSurface.withAlpha(200)),
                        overflow: TextOverflow.ellipsis,
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}
