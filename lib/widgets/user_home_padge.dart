import 'package:flutter/material.dart';

class UserHomePadge extends StatelessWidget {
  const UserHomePadge({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Container(
      height: size.height * 0.08,
      width: size.width * 0.45,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: size.height * 0.04,
            backgroundImage: AssetImage('assets/stocks/profile.jpg'),
          ),
          SizedBox(
            width: 5,
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Text(
                  'Jhon doe',
                  style: text.bodyLarge!.copyWith(
                      color: color.onSurface, fontWeight: FontWeight.bold),
                ),
                Text(
                  '@jhon123',
                  style: text.bodySmall,
                )
              ],
            ),
          )
        ],
      ),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(120),
          color: color.primary.withAlpha(180)),
    );
  }
}
