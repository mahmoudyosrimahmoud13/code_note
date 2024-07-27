import 'package:code_note/widgets/note_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class HomeGridView extends StatelessWidget {
  HomeGridView({super.key});

  final List<NoteCard> notes = [
    NoteCard(
      lastModified: '2024-07-21',
      title: 'Grocery List',
      body: 'Milk, Eggs, Bread, Butter, Cheese',
    ),
    NoteCard(
      lastModified: '2024-07-19',
      title: 'Meeting Notes',
      body: 'Discuss project milestones, assign tasks, set deadlines.',
    ),
    NoteCard(
      lastModified: '2024-07-18',
      title: 'Workout Routine',
      body:
          'Monday: Chest, Tuesday: Back, Wednesday: Legs, Thursday: Shoulders, Friday: Arms.',
    ),
    NoteCard(
      lastModified: '2024-07-17',
      title: 'Travel Itinerary',
      body:
          'Day 1: Arrive in Paris, Day 2: Visit Eiffel Tower, Day 3: Louvre Museum.',
    ),
    NoteCard(
      lastModified: '2024-07-16',
      title: 'Books to Read',
      body:
          '1984 by George Orwell, To Kill a Mockingbird by Harper Lee, The Great Gatsby by F. Scott Fitzgerald.',
    ),
    NoteCard(
      lastModified: '2024-07-15',
      title: 'Recipe: Chocolate Cake',
      body:
          'Ingredients: Flour, Cocoa Powder, Baking Powder, Eggs, Sugar, Butter, Milk. Instructions: Mix, bake at 350°F for 30 minutes.',
    ),
    NoteCard(
      lastModified: '2024-07-14',
      title: 'Study Schedule',
      body:
          'Monday: Math, Tuesday: Science, Wednesday: History, Thursday: Literature, Friday: Art.',
    ),
    NoteCard(
      lastModified: '2024-07-13',
      title: 'Project Ideas',
      body:
          'Build a mobile app, create a personal blog, design a game, start a YouTube channel.',
    ),
    NoteCard(
      lastModified: '2024-07-12',
      title: 'Budget Plan',
      body:
          'Income: \$5000, Expenses: Rent \$1500, Food \$500, Utilities \$200, Savings \$1000.',
    ),
    NoteCard(
      lastModified: '2024-07-11',
      title: 'Weekly Goals',
      body:
          'Complete project report, finish reading a book, exercise 3 times, call family.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MasonryGridView.builder(
        gridDelegate:
            SliverSimpleGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
        itemCount: notes.length,
        itemBuilder: (context, index) {
          return notes[index];
        },
      ),
    );
  }
}
