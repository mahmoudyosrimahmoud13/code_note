import 'package:code_note/cubit/note/note_cubit.dart';
import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/models/note_model.dart';
import 'package:code_note/screens/note/note_screen.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:code_note/widgets/home_grid_view.dart';
import 'package:code_note/widgets/home_navigation_bar.dart';
import 'package:code_note/widgets/user_home_padge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final noteCubit =
      BlocProvider.of<NoteCubit>(navigatorKey.currentState!.context);

  @override
  void initState() {
    // TODO: implement initState
    noteCubit.initializeNote(notes: notes);

    super.initState();
  }

  void addNote(NoteSuccess state) async {
    final Note note =
        Note(id: uuid.generate(), lastModified: DateTime.now(), tags: []);
    Navigator.of(context)
        .push(MaterialPageRoute(
      builder: (context) => NoteScreen(note: note),
    ))
        .then(
      (value) {
        noteCubit.initializeNote(notes: notes);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<NoteCubit, NoteState>(
          builder: (context, state) {
            if (state is NoteSuccess) {
              return Stack(
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const UserHomePadge(),
                            SizedBox(
                              width: size.width * 0.4,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  CustomIconButton(icon: Icons.search),
                                  const SizedBox(
                                    width: 0,
                                  ),
                                  CustomIconButton(icon: Icons.people)
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      HomeGridView(
                        notes: notes,
                      ),
                      const SizedBox(
                        height: 40,
                      )
                    ],
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: NavBar(
                      addNote: () => addNote(state),
                    ),
                  )
                ],
              );
            } else if (state is NoteLoading) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            } else {
              return const Center(
                child: Icon(Icons.error),
              );
            }
          },
        ),
      ),
    );
  }
}
