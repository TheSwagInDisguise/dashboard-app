// 22 starter templates — port of PersonalTerminal domain/Templates.
// Health Connect auto-fill is not ported: templates tagged for it stay
// manual counters.

import '../models/habit.dart';

class HabitTemplate {
  const HabitTemplate({
    required this.id,
    required this.name,
    this.type = HabitType.checkbox,
    this.target = 1,
    this.unit = '',
    this.color = 'green',
    this.schedule = ScheduleType.daily,
    this.daysMask = 127,
    this.timesPerWeek = 3,
    this.reminderMinutes = -1,
    this.negative = false,
    required this.group,
    required this.description,
  });

  final String id;
  final String name;
  final HabitType type;
  final int target;
  final String unit;
  final String color;
  final ScheduleType schedule;
  final int daysMask;
  final int timesPerWeek;
  final int reminderMinutes;
  final bool negative;
  final String group;
  final String description;
}

class HabitTemplates {
  HabitTemplates._();

  static const List<HabitTemplate> all = [
    // ---- health
    HabitTemplate(id: 'water', name: 'drink water', type: HabitType.counter, target: 8, unit: 'cups', color: 'cyan', group: 'health', description: '8 cups a day; tap +1 per glass'),
    HabitTemplate(id: 'steps', name: 'walk 8k steps', type: HabitType.counter, target: 8000, unit: 'steps', color: 'green', group: 'health', description: '8,000 steps; tap or log it'),
    HabitTemplate(id: 'workout', name: 'workout', color: 'red', schedule: ScheduleType.weekly, timesPerWeek: 3, group: 'health', description: '3 sessions a week, any day'),
    HabitTemplate(id: 'stretch', name: 'stretch', color: 'green', reminderMinutes: 7 * 60 + 30, group: 'health', description: '5 minutes every morning'),
    HabitTemplate(id: 'sleep', name: 'in bed by 23:00', color: 'purple', reminderMinutes: 22 * 60 + 30, group: 'health', description: 'reminder half an hour before'),
    HabitTemplate(id: 'vitamins', name: 'take vitamins', color: 'yellow', reminderMinutes: 8 * 60, group: 'health', description: 'daily, with breakfast'),
    // ---- mind
    HabitTemplate(id: 'meditate', name: 'meditate', type: HabitType.timer, target: 10, unit: 'min', color: 'purple', group: 'mind', description: '10 minutes; use the timer'),
    HabitTemplate(id: 'read', name: 'read', type: HabitType.counter, target: 20, unit: 'pages', color: 'yellow', group: 'mind', description: '20 pages a day'),
    HabitTemplate(id: 'journal', name: 'journal', color: 'pink', reminderMinutes: 21 * 60, group: 'mind', description: 'three lines before bed'),
    HabitTemplate(id: 'gratitude', name: 'gratitude note', color: 'orange', group: 'mind', description: 'one thing that went well'),
    HabitTemplate(id: 'language', name: 'language practice', type: HabitType.timer, target: 15, unit: 'min', color: 'cyan', group: 'mind', description: '15 focused minutes'),
    // ---- work
    HabitTemplate(id: 'deepwork', name: 'deep work', type: HabitType.timer, target: 90, unit: 'min', color: 'orange', schedule: ScheduleType.specificDays, daysMask: 31, group: 'work', description: '90 min of focus on weekdays'),
    HabitTemplate(id: 'commit', name: 'commit code', color: 'green', schedule: ScheduleType.specificDays, daysMask: 31, group: 'work', description: 'ship something every weekday'),
    HabitTemplate(id: 'inbox', name: 'inbox zero', color: 'blue', schedule: ScheduleType.specificDays, daysMask: 31, group: 'work', description: 'clear the inbox before logging off'),
    HabitTemplate(id: 'plan', name: 'plan tomorrow', color: 'cyan', reminderMinutes: 17 * 60 + 30, group: 'work', description: '3 priorities for the next day'),
    // ---- avoid
    HabitTemplate(id: 'nosugar', name: 'no sugar', negative: true, color: 'red', group: 'avoid', description: 'avoid-habit: log a slip if it happens'),
    HabitTemplate(id: 'noalcohol', name: 'no alcohol', negative: true, color: 'red', schedule: ScheduleType.specificDays, daysMask: 31, group: 'avoid', description: 'dry weekdays'),
    HabitTemplate(id: 'nophone', name: 'no phone in bed', negative: true, color: 'purple', group: 'avoid', description: 'avoid-habit; streak grows on clean days'),
    HabitTemplate(id: 'nosnooze', name: 'no snooze', negative: true, color: 'orange', group: 'avoid', description: 'up on the first alarm'),
    HabitTemplate(id: 'nosmoke', name: 'no smoking', negative: true, color: 'red', group: 'avoid', description: 'one day at a time'),
    // ---- watch
    HabitTemplate(id: 'wind', name: 'wind the watch', color: 'cyan', reminderMinutes: 7 * 60, group: 'watch', description: 'manual movements want a morning wind'),
    HabitTemplate(id: 'wristshot', name: 'wrist shot', color: 'pink', group: 'watch', description: "log today's watch with a photo"),
  ];

  static List<String> get groups => all.map((t) => t.group).toSet().toList();

  static List<HabitTemplate> byGroup(String group) => all.where((t) => t.group == group).toList();

  static HabitTemplate? find(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
