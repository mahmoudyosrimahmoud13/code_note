import 'dart:io';

import 'package:code_note/cubit/note/note_cubit.dart';
import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/models/note_model.dart';
import 'package:code_note/screens/note/note_screen.dart';
import 'package:code_note/widgets/block/image_block.dart';
import 'package:code_note/widgets/block/note_block.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NoteCard extends StatelessWidget {
  NoteCard({super.key, required this.note}) {
    lastModified = note.lastModified;
    title = note.title;
    for (int i = 0; i < note.blocks!.length; i++) {
      if (note.blocks![i] is NoteBlock) {
        body = note.blocks![i].toString();
        break;
      } else {
        body = 'empty note.';
      }
    }
    for (int i = 0; i < note.blocks!.length; i++) {
      if (note.blocks![i] is ImageBlock) {
        image = note.blocks![i].image;
      }
    }
  }
  final Note note;
  DateTime? lastModified;
  File? image;
  String? title;
  String? body;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Dismissible(
      secondaryBackground: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.secondary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: Icon(
            Icons.archive,
            color: color.onSecondary,
          ),
        ),
      ),
      background: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.error,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(
            Icons.delete,
            color: color.onError,
          ),
        ),
      ),
      onDismissed: (direction) {
        notes.removeWhere(
          (element) => element.id == note.id,
        );
      },
      key: UniqueKey(),
      child: Stack(
        children: [
          InkWell(
            onTap: () => navigateTo(
                toPage: NoteScreen(
              note: note,
            )),
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: color.onSurface.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
              ),
              width: double.infinity,
              child: Column(
                children: [
                  image != null
                      ? Container(
                          width: double.infinity,
                          height: size.height * 0.2,
                          decoration: BoxDecoration(
                              color: color.onSurface.withAlpha(30),
                              borderRadius: BorderRadius.circular(20),
                              image: DecorationImage(
                                image: FileImage(image!),
                                fit: BoxFit.cover,
                              )),
                        )
                      : const SizedBox.shrink(),
                  Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat.yMEd().format(lastModified!),
                          style: textTheme.bodySmall!
                              .copyWith(color: color.secondary),
                        ),
                        title != null
                            ? Text(title!,
                                style: textTheme.headlineMedium!.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: color.onSurface))
                            : const SizedBox.shrink(),
                        Text(
                          body!,
                          style: textTheme.bodyLarge!
                              .copyWith(color: color.onSurface),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Container(
              margin: const EdgeInsets.all(3),
              alignment: Alignment.center,
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                  color: Colors.amber,
                  border: Border.all(width: 1, color: color.onSurface),
                  borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20))),
              child: IconButton(
                icon: const Icon(
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
    );
  }
}
