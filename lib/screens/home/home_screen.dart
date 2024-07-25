import 'package:code_note/screens/authentication/sign_up_screen.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:code_note/widgets/home_navigation_bar.dart';
import 'package:code_note/widgets/user_home_padge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  UserHomePadge(),
                  Container(
                    width: size.width * 0.4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        CustomIconButton(icon: Icons.search),
                        SizedBox(
                          width: 0,
                        ),
                        CustomIconButton(icon: Icons.people)
                      ],
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
      bottomNavigationBar: NavBar(
        currentIndex: _currentIndex,
        ontap: (value) {
          setState(() {
            _currentIndex = value;
          });
        },
      ),
    );
  }
}
