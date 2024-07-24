import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/screens/authentication/login.dart';
import 'package:code_note/screens/authentication/sign_up_screen.dart';
import 'package:code_note/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            child: Stack(children: [
              Container(
                height: size.height * 0.55,
              ),
              Container(
                height: size.height * 0.45,
                decoration: BoxDecoration(
                    image: DecorationImage(
                        image: AssetImage('assets/background/start_image.jpg'),
                        fit: BoxFit.cover),
                    borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(100),
                        bottomRight: Radius.circular(100))),
              ),
              Positioned(
                  top: size.height * 0.36,
                  left: size.width * 0.5 - 60,
                  child: Container(
                      height: 120,
                      width: 120,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(180),
                          image: DecorationImage(
                              image: AssetImage('assets/logo/logo.png'),
                              opacity: 10))))
            ]),
          ),
          Padding(
            padding: EdgeInsets.all(0),
            child: Text(
              'Code note',
              style: text.displayMedium!.copyWith(color: color.primary),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              'Capture Code, Capture Ideas',
              style: text.titleLarge!.copyWith(color: color.secondary),
            ),
          ),
          Padding(
              padding: const EdgeInsets.all(30),
              child: CustomButton(
                onPressed: () => navigateTo(toPage: SignUpScreen()),
                text: 'Get started now',
                icon:
                    Icon(Icons.navigate_next_outlined, color: color.onSurface),
              )),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 100, vertical: 10),
            child: Divider(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'You already have an account,',
                style: text.bodyLarge!.copyWith(color: color.onSurface),
              ),
              InkWell(
                onTap: () => navigateTo(toPage: LoginScreen()),
                child: Text(
                  'Login',
                  style: text.bodyLarge!.copyWith(color: color.primary),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }
}
