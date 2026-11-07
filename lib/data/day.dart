/// A plan day ends at this hour, so a 0:30 workout counts for the evening
/// before.
const dayEndHour = 4;

String _two(int v) => v.toString().padLeft(2, '0');

/// Day keys are `yyyy-MM-dd`, so they also compare correctly as strings.
String dayKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

DateTime parseDay(String key) => DateTime.parse(key);

/// The plan day that local time [now] belongs to.
String logicalDay(DateTime now) =>
    dayKey(now.subtract(const Duration(hours: dayEndHour)));

String addDays(String key, int days) {
  final d = parseDay(key);
  return dayKey(DateTime(d.year, d.month, d.day + days));
}

const _weekdayGenitive = [
  'poniedziałku',
  'wtorku',
  'środy',
  'czwartku',
  'piątku',
  'soboty',
  'niedzieli',
];

String weekdayGenitive(String key) =>
    _weekdayGenitive[parseDay(key).weekday - 1];

String formatDay(String key) {
  final d = parseDay(key);
  return '${d.day}.${_two(d.month)}.${d.year}';
}
