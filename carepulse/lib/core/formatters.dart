const months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String dateLabel(DateTime value) =>
    '${months[value.month - 1]} ${value.day}, ${value.year}';

String timeLabel(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '$hour:${value.minute.toString().padLeft(2, '0')}${value.hour < 12 ? ' AM' : ' PM'}';
}

String shortDateLabel(DateTime value) => dateLabel(value).replaceFirst(
  months[value.month - 1],
  months[value.month - 1].substring(0, 3),
);
