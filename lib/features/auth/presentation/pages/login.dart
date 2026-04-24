import '../../../notes/presentation/pages/home_page.dart';
import '../../../../helpers/helper_methods.dart';
import 'sign_up_screen.dart';
import 'start.dart';
import '../../../../widgets/custom_button.dart';
import '../../../../widgets/custom_textfield.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool showPassword = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Container(
            padding: EdgeInsets.all(20),
            height: double.infinity,
            width: double.infinity,
            child: Form(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image(
                        image: AssetImage('assets/logo/light.png'),
                        height: 75,
                        width: 75,
                      ),
                      SizedBox(
                        width: 10,
                      ),
                      Text(
                        'Code note',
                        style: text.headlineLarge!
                            .copyWith(color: color.onSurface),
                      )
                    ],
                  ),
                  SizedBox(
                    height: 10,
                  ),
                  Center(
                    child: Text(
                      'Your code, notes and ideas, all at the same place.',
                      style: text.titleLarge!.copyWith(
                        color: color.secondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(
                    height: 40,
                  ),
                  Text(
                    'Email:',
                    style: TextStyle(color: color.onSurface),
                  ),
                  SizedBox(
                    height: 10,
                  ),
                  CustomTextfield(
                    hint: 'ex@example.com',
                  ),
                  SizedBox(
                    height: 20,
                  ),
                  Text(
                    'Password:',
                    style: TextStyle(color: color.onSurface),
                  ),
                  SizedBox(
                    height: 10,
                  ),
                  CustomTextfield(
                    hint: 'Password',
                    obscureText: showPassword,
                    icon: IconButton(
                      icon: Icon(showPassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () {
                        setState(() {
                          showPassword = showPassword ? false : true;
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    height: 20,
                  ),
                  InkWell(
                    onTap: () => navigateTo(toPage: StartScreen()),
                    child: Text(
                      'Forgot password?',
                      style: text.bodyMedium!.copyWith(color: color.primary),
                    ),
                  ),
                  SizedBox(
                    height: 20,
                  ),
                  Container(
                    width: double.infinity,
                    child: CustomButton(
                      text: 'Login',
                      onPressed: () => navigateTo(toPage: const HomePage(), replace: true),
                      icon: Icon(
                        Icons.navigate_next_rounded,
                        color: color.onSurface,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 20,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("You don't have an account,",
                          style: text.bodyMedium!
                              .copyWith(color: color.onSurface)),
                      InkWell(
                        onTap: () =>
                            navigateTo(toPage: SignUpScreen(), replace: true),
                        child: Text('Sign up.',
                            style: text.bodyMedium!
                                .copyWith(color: color.primary)),
                      )
                    ],
                  )
                ],
              ),
            )),
      ),
    );
  }
}
