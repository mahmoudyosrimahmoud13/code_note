import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:random_avatar/random_avatar.dart';

class UserAvatar extends StatefulWidget {
  final String? imageUrl;
  final String? seed;
  final double radius;

  const UserAvatar({
    super.key,
    this.imageUrl,
    this.seed,
    this.radius = 20,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  bool _hasError = false;

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      setState(() {
        _hasError = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty && !_hasError) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: Colors.transparent,
        child: ClipOval(
          child: _buildImage(widget.imageUrl!),
        ),
      );
    }

    return _buildFallback();
  }

  Widget _buildImage(String url) {
    if (url.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: url,
        width: widget.radius * 2,
        height: widget.radius * 2,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildFallback(),
        errorWidget: (context, url, error) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _hasError = true);
          });
          return _buildFallback();
        },
      );
    } else {
      final file = File(url);
      if (!kIsWeb && file.existsSync()) {
        return Image.file(
          file,
          width: widget.radius * 2,
          height: widget.radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _hasError = true);
            });
            return _buildFallback();
          },
        );
      } else {
        // If web and not http, or file doesn't exist
        return _buildFallback();
      }
    }
  }

  Widget _buildFallback() {
    return Container(
      width: widget.radius * 2,
      height: widget.radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withAlpha(80),
            Theme.of(context).colorScheme.secondary.withAlpha(80),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: RandomAvatar(
        widget.seed ?? 'default',
        height: widget.radius * 2,
        width: widget.radius * 2,
      ),
    );
  }
}
