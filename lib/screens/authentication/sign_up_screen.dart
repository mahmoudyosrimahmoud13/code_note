import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/screens/authentication/login.dart';
import 'package:code_note/screens/authentication/start.dart';
import 'package:code_note/widgets/custom_button.dart';
import 'package:code_note/widgets/custom_textfield.dart';
import 'package:flutter/material.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
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
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  SizedBox(
                    height: 30,
                  ),
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
                    'Full name:',
                    style: TextStyle(color: color.onSurface),
                  ),
                  SizedBox(
                    height: 10,
                  ),
                  CustomTextfield(
                    hint: 'Jhon doe',
                  ),
                  SizedBox(
                    height: 10,
                  ),
                  Text(
                    'Username:',
                    style: TextStyle(color: color.onSurface),
                  ),
                  SizedBox(
                    height: 10,
                  ),
                  CustomTextfield(
                    hint: 'Jhon123',
                  ),
                  SizedBox(
                    height: 10,
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
                  Container(
                    width: double.infinity,
                    child: CustomButton(
                      text: 'Sign up',
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
                      Text("You already have an account,",
                          style: text.bodyMedium!
                              .copyWith(color: color.onSurface)),
                      InkWell(
                        onTap: () =>
                            navigateTo(toPage: LoginScreen(), replace: true),
                        child: Text('Login.',
                            style: text.bodyMedium!
                                .copyWith(color: color.primary)),
                      )
                    ],
                  ),
                ])),
          ),
        ),
      ),
    );
  }
}
