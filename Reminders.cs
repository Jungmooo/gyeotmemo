using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

namespace GyeotMemo
{
    public sealed class ScheduleResult
    {
        public DateTime? DueAt { get; set; }
        public DateTime? MorningAt { get; set; }
        public DateTime? AfternoonAt { get; set; }
        public string Hint { get; set; }
    }

    public static class ScheduleParser
    {
        private static readonly Regex RelativeDate = Pattern(@"오늘|내일|모레");
        private static readonly Regex KoreanDate = Pattern(@"(?<!\d)(?:(?<year>\d{4})\s*년\s*)?(?<month>\d{1,2})\s*월\s*(?<day>\d{1,2})\s*일");
        private static readonly Regex NumericDate = Pattern(@"(?<![\d./-])(?:(?<year>\d{4})\s*[-./]\s*)?(?<month>\d{1,2})\s*[-./]\s*(?<day>\d{1,2})(?![\d./-])");
        private static readonly Regex DayOnly = Pattern(@"(?<!\d)(?<day>\d{1,2})\s*일(?![간동안])");
        private static readonly Regex Time = Pattern(@"(?<![\d:])(?:(?<period>오전|오후|아침|저녁|밤|새벽|낮)\s*)?(?<hour>\d{1,2})\s*(?::\s*(?<colonMinute>\d{2})(?![\d:])|시(?!간)(?:\s*(?:(?<minute>\d{1,2})\s*분(?![\d])|(?<half>반)))?)");
        private static readonly Regex Weekday = Pattern(@"(?<day>[일월화수목금토])요일");
        private static readonly Regex UnsupportedDate = Pattern(@"어제|그제|매일|매주|매월|매년|다음\s*주|이번\s*주|다음\s*달");
        private static Regex Pattern(string expression)
        {
            return new Regex(expression, RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));
        }

        public static ScheduleResult Parse(string text, DateTime now)
        {
            text = text ?? "";
            MatchCollection times = Time.Matches(text);
            MatchCollection relativeDates = RelativeDate.Matches(text);
            MatchCollection koreanDates = KoreanDate.Matches(text);
            MatchCollection numericDates = NumericDate.Matches(text);
            MatchCollection weekdays = Weekday.Matches(text);
            // Avoid reading the day portion of a full date as a second date.
            MatchCollection dayDates = DayOnly.Matches(KoreanDate.Replace(NumericDate.Replace(text, " "), " "));
            int dateCount = relativeDates.Count + koreanDates.Count + numericDates.Count + dayDates.Count;
            if (times.Count == 0)
                return new ScheduleResult { Hint = dateCount > 0 ? "알림을 받으려면 시간도 적어 주세요" : "" };
            if (times.Count != 1 || dateCount > 1 || weekdays.Count > 1)
                return new ScheduleResult { Hint = "알림 날짜와 시간을 하나씩 적어 주세요" };
            if (UnsupportedDate.IsMatch(text))
                return new ScheduleResult { Hint = "알림 날짜를 월·일 또는 오늘·내일·모레로 적어 주세요" };

            Match time = times[0];
            int hour = int.Parse(time.Groups["hour"].Value, CultureInfo.InvariantCulture);
            int minute = time.Groups["half"].Success ? 30 : 0;
            if (time.Groups["colonMinute"].Success) minute = int.Parse(time.Groups["colonMinute"].Value, CultureInfo.InvariantCulture);
            if (time.Groups["minute"].Success) minute = int.Parse(time.Groups["minute"].Value, CultureInfo.InvariantCulture);
            string period = time.Groups["period"].Value;
            if (minute > 59 || hour > 23 || (period.Length > 0 && (hour < 1 || hour > 12)))
                return new ScheduleResult { Hint = "시간을 확인해 주세요 · 예: 오후 3시, 15:30" };
            if (period.Length > 0)
            {
                hour %= 12;
                if (period == "오후" || period == "저녁" || period == "낮" || (period == "밤" && int.Parse(time.Groups["hour"].Value) != 12))
                    hour += 12;
            }

            DateTime? date = now.Date;
            if (relativeDates.Count > 0)
            {
                string relative = relativeDates[0].Value;
                date = now.Date.AddDays(relative == "내일" ? 1 : relative == "모레" ? 2 : 0);
            }
            else if (koreanDates.Count > 0 || numericDates.Count > 0)
            {
                Match match = koreanDates.Count > 0 ? koreanDates[0] : numericDates[0];
                int month = int.Parse(match.Groups["month"].Value, CultureInfo.InvariantCulture);
                int day = int.Parse(match.Groups["day"].Value, CultureInfo.InvariantCulture);
                date = null;
                if (match.Groups["year"].Success)
                    date = CreateDate(int.Parse(match.Groups["year"].Value, CultureInfo.InvariantCulture), month, day);
                else
                {
                    // A missing year means the next occurrence of that calendar day.
                    for (int year = now.Year; year <= Math.Min(now.Year + 8, 9999); year++)
                    {
                        DateTime? candidate = CreateDate(year, month, day);
                        if (candidate.HasValue && candidate.Value >= now.Date) { date = candidate; break; }
                    }
                }
            }
            else if (dayDates.Count > 0)
            {
                int day = int.Parse(dayDates[0].Groups["day"].Value, CultureInfo.InvariantCulture);
                DateTime month = new DateTime(now.Year, now.Month, 1);
                date = null;
                for (int offset = 0; offset < 12; offset++)
                {
                    DateTime? candidate = CreateDate(month.Year, month.Month, day);
                    if (candidate.HasValue && candidate.Value >= now.Date) { date = candidate; break; }
                    if (month.Year == 9999 && month.Month == 12) break;
                    month = month.AddMonths(1);
                }
            }
            if (!date.HasValue) return new ScheduleResult { Hint = "날짜를 확인해 주세요" };
            if (weekdays.Count == 1)
            {
                int weekday = "일월화수목금토".IndexOf(weekdays[0].Groups["day"].Value, StringComparison.Ordinal);
                if (dateCount == 0)
                    date = now.Date.AddDays((weekday - (int)now.DayOfWeek + 7) % 7);
                else if ((int)date.Value.DayOfWeek != weekday)
                    return new ScheduleResult { Hint = date.Value.ToString("M월 d일은 dddd", CultureInfo.GetCultureInfo("ko-KR")) + "이에요 · 날짜와 요일을 확인해 주세요" };
            }
            if (period.Length == 0 && !time.Groups["colonMinute"].Success && hour >= 1 && hour <= 12)
            {
                DateTime morning = date.Value.AddHours(hour % 12).AddMinutes(minute);
                return new ScheduleResult
                {
                    MorningAt = morning,
                    AfternoonAt = morning.AddHours(12),
                    Hint = "오전인지 오후인지 선택해 주세요"
                };
            }
            return new ScheduleResult { DueAt = date.Value.AddHours(hour).AddMinutes(minute), Hint = "" };
        }

        private static DateTime? CreateDate(int year, int month, int day)
        {
            if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1 || day > DateTime.DaysInMonth(year, month)) return null;
            return new DateTime(year, month, day);
        }
    }

    public static class ReminderPlanner
    {
        public static List<TodoItem> Due(IEnumerable<TodoItem> items, DateTime now)
        {
            return items.Where(item =>
            {
                DateTime? due = item.DueAt;
                return !item.Completed && !item.Editing && due.HasValue && due.Value > now &&
                    due.Value - now <= TimeSpan.FromMinutes(30) && item.ReminderSentFor != item.ScheduledFor;
            }).OrderBy(item => item.DueAt).ToList();
        }
    }
}
