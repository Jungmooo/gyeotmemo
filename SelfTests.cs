using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text;

namespace GyeotMemo
{
    internal static class SelfTests
    {
        private static void Check(bool condition, string message)
        { if (!condition) throw new Exception(message); }
        public static int Run(string directory)
        {
            Directory.CreateDirectory(directory);
            string sandbox = Path.Combine(directory, "test-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(sandbox);
            List<string> report = new List<string>();
            try
            {
                var store = new MemoStore(sandbox);
                var state = store.Load();
                Check(state.Tasks.Count == 0 && state.Pinned, "Empty defaults");
                report.Add("PASS: empty startup and pinned default");
                state.Tasks.Add(new TodoItem { Text = "한글 · 실험 결과 확인 📝", Completed = true });
                state.Note = "첫 줄\r\n둘째 줄: 0.5 ~ 2.5"; state.Draft = "작성 중인 할 일";
                state.Left = -430; state.Top = 68; state.Width = 360; state.Height = 670; state.NoteHeight = 150; state.Pinned = false;
                store.Save(state);
                var loaded = new MemoStore(sandbox).Load();
                Check(loaded.Tasks[0].Text == state.Tasks[0].Text && loaded.Tasks[0].Completed && loaded.Tasks[0].Id == state.Tasks[0].Id && !loaded.Tasks[0].Editing, "Task persistence");
                Check(loaded.Note == state.Note && loaded.Draft == state.Draft && loaded.Left == -430 && loaded.Width == 360 && loaded.Height == 670 && loaded.NoteHeight == 150 && !loaded.Pinned, "State persistence");
                report.Add("PASS: Korean / Unicode, multi-line note, draft, completion, geometry and pin round-trip");
                state.Note = "두 번째 저장"; store.Save(state);
                Check(File.Exists(store.BackupPath) && !Directory.GetFiles(sandbox, "*.tmp").Any(), "Atomic backup");
                File.WriteAllText(store.FilePath, "{broken-json", Encoding.UTF8);
                var recovering = new MemoStore(sandbox); loaded = recovering.Load();
                Check(loaded.Note == "첫 줄\r\n둘째 줄: 0.5 ~ 2.5" && recovering.LoadMessage != null && !recovering.WriteBlocked, "Backup recovery");
                Check(Directory.GetFiles(sandbox, "memo.unreadable-*.json").Length == 1, "Original archive");
                recovering.Save(loaded);
                Check(new MemoStore(sandbox).Load().Tasks.Count == 1, "Recovered save");
                report.Add("PASS: atomic save, backup recovery, original archive and subsequent save");

                string futureDir = Path.Combine(sandbox, "future"); Directory.CreateDirectory(futureDir);
                string futureJson = "{\"Version\":2,\"Tasks\":[],\"Note\":\"future-format\"}";
                File.WriteAllText(Path.Combine(futureDir, "memo.json"), futureJson);
                var future = new MemoStore(futureDir); var empty = future.Load();
                Check(future.WriteBlocked, "Future schema should be protected");
                bool blocked = false; try { future.Save(empty); } catch (IOException) { blocked = true; }
                Check(blocked && File.ReadAllText(future.FilePath) == futureJson, "Future schema preservation");
                report.Add("PASS: future data format preserved without overwrite");

                string badDir = Path.Combine(sandbox, "bad"); Directory.CreateDirectory(badDir);
                File.WriteAllText(Path.Combine(badDir, "memo.json"), "null");
                var bad = new MemoStore(badDir); Check(bad.Load().Tasks.Count == 0 && !bad.WriteBlocked && bad.LoadMessage != null, "Corrupt without backup");
                Check(Directory.GetFiles(badDir, "memo.unreadable-*.json").Length == 1, "Bad file preserved");
                report.Add("PASS: damaged data without backup archived before starting empty");

                string invalidDir = Path.Combine(sandbox, "invalid-version"); Directory.CreateDirectory(invalidDir);
                File.WriteAllText(Path.Combine(invalidDir, "memo.json"), "{\"Version\":{},\"Tasks\":[]}");
                var invalid = new MemoStore(invalidDir);
                Check(invalid.Load().Tasks.Count == 0 && !invalid.WriteBlocked && invalid.LoadMessage != null, "Malformed schema recovery");
                report.Add("PASS: malformed schema field recovered without startup crash");

                string lockedDir = Path.Combine(sandbox, "locked"); Directory.CreateDirectory(lockedDir);
                var lockedStore = new MemoStore(lockedDir); lockedStore.Save(state);
                string original = File.ReadAllText(lockedStore.FilePath);
                bool failed = false;
                using (var locked = new FileStream(lockedStore.FilePath, FileMode.Open, FileAccess.Read, FileShare.None))
                { try { lockedStore.Save(new MemoState()); } catch (IOException) { failed = true; } }
                Check(failed && File.ReadAllText(lockedStore.FilePath) == original && !Directory.GetFiles(lockedDir, "*.tmp").Any(), "Locked file protection");
                report.Add("PASS: file lock leaves saved contents intact and cleans temporary file");

                var a = new TodoItem { Text = "a" }; var b = new TodoItem { Text = "b", Completed = true }; var c = new TodoItem { Text = "c", Completed = true };
                var tasks = new ObservableCollection<TodoItem>(new[] { a, b, c }); var history = new TaskHistory();
                history.Delete(tasks, new[] { b, c }); Check(tasks.Count == 1 && history.CanUndo, "Batch delete");
                history.Undo(tasks); Check(tasks.SequenceEqual(new[] { a, b, c }), "Undo restores indexes");
                tasks.Move(2, 0); Check(tasks.SequenceEqual(new[] { c, a, b }), "Reorder");
                history.Delete(tasks, new[] { a }); history.Delete(tasks, new[] { b }); history.Undo(tasks); history.Undo(tasks);
                Check(tasks.SequenceEqual(new[] { c, a, b }) && !history.CanUndo, "Stacked undo");
                state.Tasks = tasks.ToList(); store.Save(state);
                Check(new MemoStore(sandbox).Load().Tasks.Select(t => t.Text).SequenceEqual(new[] { "c", "a", "b" }), "Order round-trip");
                report.Add("PASS: batch delete, stacked undo, exact position restore and reordered persistence");
                File.WriteAllLines(Path.Combine(directory, "self-test-results.txt"), report.ToArray(), new UTF8Encoding(false));
                return 0;
            }
            catch (Exception e)
            {
                report.Add("FAIL: " + e);
                File.WriteAllLines(Path.Combine(directory, "self-test-results.txt"), report.ToArray(), new UTF8Encoding(false));
                return 1;
            }
        }
    }
}
