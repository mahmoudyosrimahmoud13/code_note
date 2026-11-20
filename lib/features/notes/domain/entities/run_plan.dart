import 'package:equatable/equatable.dart';

/// One step of a folder run: a note, and whether the run waits for it.
class RunStep {
  const RunStep(this.noteId, {required this.wait, this.primary = false});
  final String noteId;

  /// Wait until the note's code finishes before starting the next note.
  final bool wait;

  /// The last step, which keeps running (a server, usually).
  final bool primary;

  @override
  String toString() => '$noteId${primary ? '*' : wait ? '' : '&'}';
}

/// How ▶ Run folder runs a folder's notes: in [order], one after another,
/// with the [primary] note last. Saved with the folder.
class RunPlan extends Equatable {
  const RunPlan({
    this.order = const [],
    this.primary,
    this.keepRunning = const {},
    this.disabled = const {},
  });

  final List<String> order;
  final String? primary;

  /// Notes that start and keep going while the run moves on (extra servers).
  final Set<String> keepRunning;

  /// Notes left out of the folder run.
  final Set<String> disabled;

  /// The notes in run order: saved order first, then notes added to the
  /// folder since, in folder order. Notes that can't run are dropped.
  List<String> orderFor(List<String> runnable) => [
        for (final id in order)
          if (runnable.contains(id)) id,
        for (final id in runnable)
          if (!order.contains(id)) id,
      ];

  /// The primary note: the chosen one if it can run, otherwise the last
  /// note in the run.
  String? primaryFor(List<String> runnable) {
    final enabled = orderFor(runnable).where((id) => !disabled.contains(id)).toList();
    if (enabled.isEmpty) return null;
    return primary != null && enabled.contains(primary) ? primary : enabled.last;
  }

  /// What to start, in order, with the primary note always last.
  List<RunStep> steps(List<String> runnable) {
    final main = primaryFor(runnable);
    final ids = orderFor(runnable).where((id) => !disabled.contains(id) && id != main);
    return [
      for (final id in ids) RunStep(id, wait: !keepRunning.contains(id)),
      if (main != null) RunStep(main, wait: false, primary: true),
    ];
  }

  RunPlan copyWith({
    List<String>? order,
    String? primary,
    bool clearPrimary = false,
    Set<String>? keepRunning,
    Set<String>? disabled,
  }) =>
      RunPlan(
        order: order ?? this.order,
        primary: clearPrimary ? null : primary ?? this.primary,
        keepRunning: keepRunning ?? this.keepRunning,
        disabled: disabled ?? this.disabled,
      );

  Map<String, dynamic> toJson() => {
        'order': order,
        if (primary != null) 'primary': primary,
        if (keepRunning.isNotEmpty) 'keepRunning': keepRunning.toList(),
        if (disabled.isNotEmpty) 'disabled': disabled.toList(),
      };

  static RunPlan? fromJson(Object? json) {
    if (json is! Map) return null;
    List<String> list(Object? v) => v is List ? v.map((e) => e.toString()).toList() : const [];
    return RunPlan(
      order: list(json['order']),
      primary: json['primary']?.toString(),
      keepRunning: list(json['keepRunning']).toSet(),
      disabled: list(json['disabled']).toSet(),
    );
  }

  @override
  List<Object?> get props => [order, primary, keepRunning.toList()..sort(), disabled.toList()..sort()];
}
