import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/screens/note/note_screen.dart';
import 'package:flutter/material.dart';

class NoteCard extends StatelessWidget {
  const NoteCard(
      {super.key,
      required this.lastModified,
      required this.title,
      required this.body});
  final String lastModified;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Card(
        child: Dismissible(
      key: UniqueKey(),
      child: InkWell(
        onTap: () => navigateTo(toPage: NoteScreen()),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lastModified,
                    style:
                        textTheme.bodySmall!.copyWith(color: color.secondary),
                  ),
                  Text(title,
                      style: textTheme.headlineMedium!.copyWith(
                          fontWeight: FontWeight.bold, color: color.onSurface)),
                  Text(
                    body,
                    style:
                        textTheme.bodyLarge!.copyWith(color: color.onSurface),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: Container(
                alignment: Alignment.center,
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                    color: Colors.amber,
                    border: Border.all(width: 1, color: color.onSurface),
                    borderRadius: BorderRadius.only(
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(20))),
                child: IconButton(
                  icon: Icon(
                    size: 20,
                    Icons.star,
                    color: Colors.white,
                  ),
                  onPressed: () {},
                ),
              ),
            )
          ],
        ),
      ),
    ));
  }
}
