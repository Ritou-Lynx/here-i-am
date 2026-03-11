int isoWeekNumber(DateTime date) {
  // Method from https://stackoverflow.com/questions/49393231/how-to-get-day-of-year-week-of-year-from-a-datetime-dart-object
  int weekOfYear(DateTime date) {
    DateTime monday = date.subtract(Duration(days: date.weekday - 1));
    DateTime firstThursday = monday.add(Duration(days: 3));
    int week =
        ((firstThursday.difference(DateTime(firstThursday.year, 1, 1)).inDays) /
                    7)
                .floor() +
            1;
    return week;
  }

  return weekOfYear(date);
}
