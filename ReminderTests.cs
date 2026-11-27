using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace GyeotMemo
{
    internal static class ReminderTests
    {
        private static void Check(bool condition, string message)
        { if (!condition) throw new Exception(message); }

        private static void Parses(string text, DateTime now, DateTime expected)
        {
            ScheduleResult result = ScheduleParser.Parse(text, now);
            Check(result.DueAt == expected, "Schedule parse failed for " + text + ". Got " + result.DueAt + ": " + result.Hint);
        }

        public static void Run(string sandbox, List<string> report)
        {
            DateTime now = new DateTime(2026, 11, 25, 10, 0, 0);
            ScheduleResult ambiguous = ScheduleParser.Parse("2시 반 방문", now);
            Check(!ambiguous.DueAt.HasValue && (ambiguous.Hint ?? "").Contains("오전"), "A time without AM/PM must wait for confirmation.");
            Parses("26일 목요일 오후 4시 교수님 미팅", now, new DateTime(2026, 11, 26, 16, 0, 0));
            Parses("11월 26일 오후 3시 회의", now, new DateTime(2026, 11, 26, 15, 0, 0));
            Parses("11월26일오후3시30분 회의", now, new DateTime(2026, 11, 26, 15, 30, 0));
            Parses("2027년 1월 2일 오전 9시 반 실험", now, new DateTime(2027, 1, 2, 9, 30, 0));
            Parses("11/26 15:30 실험", now, new DateTime(2026, 11, 26, 15, 30, 0));
            Parses("2026-11-26 14:00 실험", now, new DateTime(2026, 11, 26, 14, 0, 0));
            Parses("2026.11.26 14:00 실험", now, new DateTime(2026, 11, 26, 14, 0, 0));
            Parses("오늘 저녁 7시 약속", now, new DateTime(2026, 11, 25, 19, 0, 0));
            Parses("내일 14:00 실험", now, new DateTime(2026, 11, 26, 14, 0, 0));
            Parses("모레 오전 10시 면담", now, new DateTime(2026, 11, 27, 10, 0, 0));
            Parses("26일 15시 회의", now, new DateTime(2026, 11, 26, 15, 0, 0));
            Parses("오후 3시 회의", now, new DateTime(2026, 11, 25, 15, 0, 0));
            Parses("오늘 오전 12시", now, new DateTime(2026, 11, 25, 0, 0, 0));
            Parses("오늘 오후 12시", now, new DateTime(2026, 11, 25, 12, 0, 0));
            Parses("내일 밤 12시", now, new DateTime(2026, 11, 26, 0, 0, 0));
            Parses("1월 2일 오전 9시", now, new DateTime(2027, 1, 2, 9, 0, 0));
            Parses("24일 14시", now, new DateTime(2026, 12, 24, 14, 0, 0));
            Parses("31일 14시", now, new DateTime(2026, 12, 31, 14, 0, 0));
            Parses("2월 29일 14시", now, new DateTime(2028, 2, 29, 14, 0, 0));
            Parses("11월 26일 목요일 오후 4시 정도 교수님 미팅", now, new DateTime(2026, 11, 26, 16, 0, 0));
            Parses("목요일 오후 4시 미팅", now, new DateTime(2026, 11, 26, 16, 0, 0));
            Parses("2026-11-26 목요일 16:00 미팅", now, new DateTime(2026, 11, 26, 16, 0, 0));
            Check(!ScheduleParser.Parse("26일 금요일 오후 4시 미팅", now).DueAt.HasValue, "Mismatched weekday should wait for a correction.");
            Check(ScheduleParser.Parse("26일 금요일 오후 4시 미팅", now).Hint.Contains("목요일"), "Weekday mismatch should explain the actual weekday.");
            report.Add("PASS: Korean and numeric dates, today/tomorrow/day-after, AM/PM, 24-hour time, half hours and calendar rollover");

            foreach (string text in new[] { "논문 읽기", "3시간 실험", "11월31일 15시", "13월26일 15시", "2026-02-29 15:00", "11/26 25:00", "11/26 15:60", "내일 오후 13시", "내일 3시~5시", "내일 모레 15시", "매일 15시 운동", "어제 15시 실험" })
                Check(!ScheduleParser.Parse(text, now).DueAt.HasValue, "Unexpected schedule: " + text);
            Check(ScheduleParser.Parse("내일 실험", now).Hint.Length > 0, "Date without time should explain how to enable reminders.");
            report.Add("PASS: invalid dates/times, durations, multiple times, unsupported recurrence and ordinary tasks are not scheduled");

            TodoItem item = new TodoItem { Text = "내일 오후 3시 회의" };
            item.UpdateSchedule(now);
            var store = new MemoStore(Path.Combine(sandbox, "reminders"));
            var state = new MemoState(); state.Tasks.Add(item); store.Save(state);
            TodoItem restored = store.Load().Tasks.Single();
            Check(restored.ScheduleSource == restored.Text && restored.DueAt == new DateTime(2026, 11, 26, 15, 0, 0), "Relative date must persist as an absolute date.");
            restored.RefreshScheduleLabel(now.AddDays(1));
            Check(restored.DueAt == item.DueAt, "Relative date drifted after midnight.");
            Check(ReminderPlanner.Due(new[] { item }, item.DueAt.Value.AddMinutes(-30).AddSeconds(-1)).Count == 0, "Reminder fired before its window.");
            Check(ReminderPlanner.Due(new[] { item }, item.DueAt.Value.AddMinutes(-30)).Count == 1, "30-minute boundary missed.");
            Check(ReminderPlanner.Due(new[] { item }, item.DueAt.Value.AddMinutes(-3)).Count == 1, "Late startup/wake catch-up missed.");
            Check(ReminderPlanner.Due(new[] { item }, item.DueAt.Value).Count == 0, "Past schedule should not alert.");
            item.Completed = true;
            Check(ReminderPlanner.Due(new[] { item }, item.DueAt.Value.AddMinutes(-10)).Count == 0, "Completed task alerted.");
            item.Completed = false; item.Editing = true;
            Check(ReminderPlanner.Due(new[] { item }, item.DueAt.Value.AddMinutes(-10)).Count == 0, "Editing task alerted.");
            item.Editing = false; item.ReminderSentFor = item.ScheduledFor; store.Save(state);
            restored = store.Load().Tasks.Single();
            Check(ReminderPlanner.Due(new[] { restored }, restored.DueAt.Value.AddMinutes(-10)).Count == 0, "Duplicate notification after restart.");
            item.Text = "내일 오후 3시 회의 자료 준비"; item.UpdateSchedule(now);
            Check(item.ReminderSentFor == item.ScheduledFor, "Description-only edit should keep sent marker.");
            item.Text = "내일 오후 4시 회의"; item.UpdateSchedule(now);
            Check(item.ReminderSentFor == null && item.DueAt.Value.Hour == 16, "Rescheduling must reset the sent marker.");
            item.Text = "회의"; item.UpdateSchedule(now);
            Check(!item.DueAt.HasValue && item.ReminderSentFor == null, "Removing date/time must cancel reminder.");
            report.Add("PASS: fixed relative dates, exact 30-minute boundary, wake/startup catch-up, completion/edit suppression, sent-state persistence and rescheduling");

            string legacyDir = Path.Combine(sandbox, "reminder-legacy"); Directory.CreateDirectory(legacyDir);
            File.WriteAllText(Path.Combine(legacyDir, "memo.json"), "{\"Version\":1,\"Tasks\":[{\"Id\":\"legacy\",\"Text\":\"내일 15시 회의\",\"Completed\":false}],\"Note\":\"기존 메모\"}");
            var legacy = new MemoStore(legacyDir).Load();
            Check(legacy.Note == "기존 메모" && legacy.Tasks[0].ScheduleSource == null, "Legacy data should load without reminder metadata.");
            legacy.Tasks[0].UpdateSchedule(now);
            Check(legacy.Tasks[0].DueAt.HasValue, "Legacy task migration failed.");
            report.Add("PASS: existing version-1 memo data loads and gains reminder metadata without changing note contents");

            for (int hour = 1; hour <= 12; hour++)
            {
                ScheduleResult result = ScheduleParser.Parse("내일 " + hour + "시 반 미팅", now);
                DateTime morning = now.Date.AddDays(1).AddHours(hour % 12).AddMinutes(30);
                Check(!result.DueAt.HasValue && result.MorningAt == morning && result.AfternoonAt == morning.AddHours(12), "AM/PM candidates wrong for hour " + hour);
            }
            Parses("내일 02:30 방문", now, new DateTime(2026, 11, 26, 2, 30, 0));
            Parses("내일 14시 반 방문", now, new DateTime(2026, 11, 26, 14, 30, 0));
            report.Add("PASS: unqualified Korean hours 1 through 12 wait for AM/PM choice; 24-hour formats remain explicit");

            TodoItem pending = new TodoItem { Text = "내일 2시 반 방문" };
            pending.UpdateSchedule(now);
            Check(pending.NeedsPeriodChoice && !pending.DueAt.HasValue && pending.MorningChoiceLabel == "오전 2:30" && pending.AfternoonChoiceLabel == "오후 2:30", "Choice labels missing.");
            Check(ReminderPlanner.Due(new[] { pending }, now.Date.AddDays(1).AddHours(2)).Count == 0, "Unconfirmed time must not alert.");
            var choiceState = new MemoState(); choiceState.Tasks.Add(pending); store.Save(choiceState);
            TodoItem pendingRestored = store.Load().Tasks.Single();
            Check(!pendingRestored.EnsureSchedule(now.AddDays(1)) && pendingRestored.NeedsPeriodChoice, "Restart should preserve pending choice without moving relative dates.");
            pendingRestored.ChoosePeriod(true, now);
            Check(pendingRestored.DueAt == new DateTime(2026, 11, 26, 14, 30, 0) && !pendingRestored.NeedsPeriodChoice, "PM choice did not resolve the stored date.");
            Check(ReminderPlanner.Due(new[] { pendingRestored }, new DateTime(2026, 11, 26, 14, 0, 0)).Count == 1, "Confirmed PM event should alert 30 minutes before.");
            choiceState.Tasks[0] = pendingRestored; store.Save(choiceState);
            TodoItem chosen = store.Load().Tasks.Single();
            Check(!chosen.EnsureSchedule(now.AddDays(2)) && chosen.DueAt == pendingRestored.DueAt && !chosen.NeedsPeriodChoice, "Confirmed AM/PM should survive restart.");
            chosen.Text = "내일 2시 반 방문 · 자료 준비"; chosen.UpdateSchedule(now);
            Check(chosen.DueAt == pendingRestored.DueAt && !chosen.NeedsPeriodChoice, "Description-only edit should preserve an explicit choice.");
            chosen.Text = "내일 3시 반 방문"; chosen.UpdateSchedule(now);
            Check(chosen.NeedsPeriodChoice && !chosen.DueAt.HasValue, "Changing an ambiguous hour should ask again.");
            chosen.ChoosePeriod(false, now);
            Check(chosen.DueAt == new DateTime(2026, 11, 26, 3, 30, 0), "AM choice failed.");
            report.Add("PASS: inline AM/PM labels, no unconfirmed reminders, both choices, pending/confirmed restart persistence and edit behavior");

            TodoItem oldAmbiguous = new TodoItem
            {
                Text = "2시 반 방문", ScheduleSource = "2시 반 방문", ScheduledFor = "2026-11-25T02:30:00", ReminderSentFor = "2026-11-25T02:30:00"
            };
            Check(oldAmbiguous.EnsureSchedule(now.AddDays(1)) && oldAmbiguous.NeedsPeriodChoice && oldAmbiguous.ReminderSentFor == null && oldAmbiguous.PendingMorningFor == "2026-11-25T02:30:00", "Legacy ambiguity must ask again while preserving its original calendar date.");
            TodoItem oldRelative = new TodoItem { Text = "내일 2시 반 방문", ScheduleSource = "내일 2시 반 방문", ScheduledFor = "2026-11-26T02:30:00" };
            oldRelative.EnsureSchedule(now.AddDays(1));
            Check(oldRelative.NeedsPeriodChoice && oldRelative.PendingAfternoonFor == "2026-11-26T14:30:00", "Legacy relative date moved during AM/PM migration.");
            TodoItem oldFixed = new TodoItem { Text = "내일 오후 4시 미팅", ScheduleSource = "내일 오후 4시 미팅", ScheduledFor = "2026-11-26T16:00:00", ReminderSentFor = "2026-11-26T16:00:00" };
            oldFixed.EnsureSchedule(now.AddDays(1));
            Check(oldFixed.ScheduledFor == "2026-11-26T16:00:00" && oldFixed.ReminderSentFor == oldFixed.ScheduledFor, "Explicit legacy schedule or sent marker changed.");
            TodoItem oldWeekday = new TodoItem { Text = "26일 목요일 오후 4시 교수님 미팅", ScheduleSource = "26일 목요일 오후 4시 교수님 미팅", ScheduleHint = "알림 날짜를 월·일 또는 오늘·내일·모레로 적어 주세요" };
            oldWeekday.EnsureSchedule(now.AddDays(1));
            Check(oldWeekday.DueAt == new DateTime(2026, 11, 26, 16, 0, 0), "Existing weekday task did not gain its reminder.");
            report.Add("PASS: existing ambiguous times gain confirmation while fixed dates and sent state stay stable; existing weekday task reparses correctly");
        }
    }
}
