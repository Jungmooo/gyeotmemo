using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

namespace GyeotMemo
{
    public sealed class TodoItem : INotifyPropertyChanged
    {
        private string text = "";
        private bool completed;
        private bool editing;
        public string Id { get; set; }
        public string Text { get { return text; } set { if (text != value) { text = value ?? ""; Notify("Text"); } } }
        public bool Completed { get { return completed; } set { if (completed != value) { completed = value; Notify("Completed"); } } }
        [ScriptIgnore]
        public bool Editing { get { return editing; } set { editing = value; Notify("Editing"); } }
        public TodoItem() { Id = Guid.NewGuid().ToString("N"); }
        public event PropertyChangedEventHandler PropertyChanged;
        private void Notify(string name) { if (PropertyChanged != null) PropertyChanged(this, new PropertyChangedEventArgs(name)); }
    }

    public sealed class MemoState
    {
        public int Version { get; set; }
        public List<TodoItem> Tasks { get; set; }
        public string Note { get; set; }
        public string Draft { get; set; }
        public bool Pinned { get; set; }
        public double Width { get; set; }
        public double Height { get; set; }
        public double? Left { get; set; }
        public double? Top { get; set; }
        public double NoteHeight { get; set; }
        public MemoState()
        {
            Version = 1; Tasks = new List<TodoItem>(); Note = ""; Draft = "";
            Pinned = true; Width = 380; Height = 650; NoteHeight = 136;
        }
    }

    public sealed class MemoStore
    {
        private readonly string directory;
        public string FilePath { get { return Path.Combine(directory, "memo.json"); } }
        public string BackupPath { get { return Path.Combine(directory, "memo.backup.json"); } }
        public string LoadMessage { get; private set; }
        public bool WriteBlocked { get; private set; }
        private static JavaScriptSerializer Serializer()
        {
            return new JavaScriptSerializer { MaxJsonLength = 8 * 1024 * 1024, RecursionLimit = 32 };
        }
        public MemoStore(string directory) { this.directory = directory; }
        private MemoState Read(string path)
        {
            string json = File.ReadAllText(path, Encoding.UTF8);
            // Reject missing schema and future formats instead of silently replacing them.
            Dictionary<string, object> root = Serializer().DeserializeObject(json) as Dictionary<string, object>;
            if (root == null || !root.ContainsKey("Version") || !(root["Version"] is int) || (int)root["Version"] != 1 || !root.ContainsKey("Tasks"))
                throw new InvalidDataException("지원하지 않는 저장 형식입니다.");
            MemoState state = Serializer().Deserialize<MemoState>(json);
            if (state == null || state.Tasks == null) throw new InvalidDataException("할 일 목록을 읽지 못했습니다.");
            HashSet<string> ids = new HashSet<string>();
            foreach (TodoItem task in state.Tasks)
            {
                if (task == null || task.Text == null) throw new InvalidDataException("잘못된 할 일입니다.");
                if (string.IsNullOrEmpty(task.Id) || !ids.Add(task.Id))
                { task.Id = Guid.NewGuid().ToString("N"); ids.Add(task.Id); }
            }
            state.Note = state.Note ?? ""; state.Draft = state.Draft ?? "";
            return state;
        }
        public MemoState Load()
        {
            LoadMessage = null; WriteBlocked = false;
            if (!File.Exists(FilePath))
            {
                if (File.Exists(BackupPath))
                {
                    try { MemoState backup = Read(BackupPath); LoadMessage = "백업에서 메모를 복원했습니다."; return backup; }
                    catch (Exception e) when (IsStorageError(e)) { WriteBlocked = true; LoadMessage = "백업을 읽지 못했습니다. 원본 파일을 확인해 주세요."; }
                }
                return new MemoState();
            }
            try { return Read(FilePath); }
            catch (Exception e) when (IsStorageError(e))
            {
                // A future schema must never be downgraded by this version.
                try
                {
                    var root = Serializer().DeserializeObject(File.ReadAllText(FilePath, Encoding.UTF8)) as Dictionary<string, object>;
                    if (root != null && root.ContainsKey("Version") && root["Version"] is int && (int)root["Version"] > 1)
                    { WriteBlocked = true; LoadMessage = "더 새로운 버전의 메모입니다. 저장을 중단했습니다."; return new MemoState(); }
                }
                catch (Exception checkError) when (IsStorageError(checkError)) { }
                try
                {
                    Directory.CreateDirectory(directory);
                    string archive = Path.Combine(directory, "memo.unreadable-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + "-" + Guid.NewGuid().ToString("N").Substring(0, 6) + ".json");
                    File.Copy(FilePath, archive, false);
                }
                catch (Exception archiveError) when (IsStorageError(archiveError))
                { WriteBlocked = true; LoadMessage = "저장 파일을 읽거나 보관하지 못했습니다. 원본 파일을 확인해 주세요."; return new MemoState(); }
                try
                {
                    MemoState backup = Read(BackupPath);
                    LoadMessage = "백업에서 복원했습니다. 읽지 못한 원본도 보관했습니다.";
                    return backup;
                }
                catch (Exception backupError) when (IsStorageError(backupError))
                { LoadMessage = "읽지 못한 원본을 보관하고 새 메모를 열었습니다."; return new MemoState(); }
            }
        }
        public void Save(MemoState state)
        {
            if (WriteBlocked) throw new IOException(LoadMessage);
            Directory.CreateDirectory(directory);
            string temporary = Path.Combine(directory, "memo." + Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                byte[] bytes = new UTF8Encoding(false).GetBytes(Serializer().Serialize(state));
                using (FileStream stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                { stream.Write(bytes, 0, bytes.Length); stream.Flush(true); }
                if (File.Exists(FilePath)) File.Replace(temporary, FilePath, BackupPath, true);
                else File.Move(temporary, FilePath);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
        private static bool IsStorageError(Exception e)
        {
            return e is IOException || e is InvalidDataException || e is UnauthorizedAccessException || e is ArgumentException ||
                e is InvalidOperationException || e is FormatException || e is OverflowException;
        }
    }

    public sealed class TaskHistory
    {
        private sealed class Removed { public TodoItem Item; public int Index; }
        private readonly Stack<List<Removed>> deletions = new Stack<List<Removed>>();
        public bool CanUndo { get { return deletions.Count > 0; } }
        public void Delete(ObservableCollection<TodoItem> tasks, IList<TodoItem> items)
        {
            List<Removed> batch = new List<Removed>();
            foreach (TodoItem item in items)
            { int index = tasks.IndexOf(item); if (index >= 0) batch.Add(new Removed { Item = item, Index = index }); }
            batch.Sort((a, b) => a.Index.CompareTo(b.Index));
            foreach (Removed item in batch) tasks.Remove(item.Item);
            if (batch.Count > 0) deletions.Push(batch);
        }
        public bool Undo(ObservableCollection<TodoItem> tasks)
        {
            if (!CanUndo) return false;
            foreach (Removed removed in deletions.Pop())
                if (!tasks.Contains(removed.Item)) tasks.Insert(Math.Min(removed.Index, tasks.Count), removed.Item);
            return true;
        }
    }
}
