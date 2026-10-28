using System;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shell;
using System.Windows.Threading;

namespace GyeotMemo
{
    internal static class Program
    {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindow(string className, string title);
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr handle);
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr handle, int command);

        [STAThread]
        private static int Main(string[] args)
        {
            string dataDirectory = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "data");
            for (int i = 0; i < args.Length - 1; i++)
                if (args[i] == "--data-dir") dataDirectory = Path.GetFullPath(args[i + 1]);
            if (args.Length > 0 && args[0] == "--self-test")
                return SelfTests.Run(dataDirectory);
            try
            {
                string instance;
                using (var hash = SHA256.Create())
                    instance = BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(dataDirectory.ToUpperInvariant()))).Replace("-", "").Substring(0, 24);
                bool first;
                using (Mutex mutex = new Mutex(true, "Local\\GyeotMemo-" + instance, out first))
                {
                    if (!first)
                    {
                        IntPtr existing = FindWindow(null, "곁메모");
                        if (existing != IntPtr.Zero) { ShowWindow(existing, 9); SetForegroundWindow(existing); }
                        return 0;
                    }
                    Application app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
                    app.DispatcherUnhandledException += delegate(object sender, DispatcherUnhandledExceptionEventArgs e)
                    {
                        // Leave the original data intact and make unexpected errors visible.
                        try { File.AppendAllText(Path.Combine(dataDirectory, "error.log"), DateTime.Now + "\r\n" + e.Exception + "\r\n", Encoding.UTF8); } catch { }
                        MessageBox.Show("문제가 발생했습니다. 메모를 보존하기 위해 프로그램을 종료합니다.\n\n" + e.Exception.Message, "곁메모", MessageBoxButton.OK, MessageBoxImage.Error);
                    };
                    MainController controller = new MainController(new MemoStore(dataDirectory));
                    return app.Run(controller.Window);
                }
            }
            catch (Exception e)
            {
                MessageBox.Show("곁메모를 열지 못했습니다.\n\n" + e.Message, "곁메모", MessageBoxButton.OK, MessageBoxImage.Error);
                return 1;
            }
        }
    }

    internal sealed class MainController
    {
        public Window Window { get; private set; }
        private readonly MemoStore store;
        private readonly MemoState saved;
        private readonly ObservableCollection<TodoItem> tasks = new ObservableCollection<TodoItem>();
        private readonly TaskHistory history = new TaskHistory();
        private readonly DispatcherTimer saveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
        private readonly DispatcherTimer dateTimer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(1) };
        private TextBox input, note;
        private ListBox list;
        private TextBlock saveLabel;
        private bool ready, dirty;
        private TodoItem editItem, dragItem;
        private string editOriginal;
        private Point dragStart;
        private string saveError;

        private T Get<T>(string name) where T : class { return Window.FindName(name) as T; }
        private static SolidColorBrush Brush(string color) { return (SolidColorBrush)new BrushConverter().ConvertFromString(color); }

        public MainController(MemoStore store)
        {
            this.store = store; saved = store.Load();
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("MainWindow.xaml"))
                Window = (Window)XamlReader.Load(stream);
            WindowChrome.SetWindowChrome(Window, new WindowChrome { CaptionHeight = 0, ResizeBorderThickness = new Thickness(6), CornerRadius = new CornerRadius(10), GlassFrameThickness = new Thickness(0), UseAeroCaptionButtons = false });
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ico"))
            { Window.Icon = BitmapFrame.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad); }
            input = Get<TextBox>("TaskInput"); note = Get<TextBox>("NoteInput"); list = Get<ListBox>("TaskList"); saveLabel = Get<TextBlock>("SaveLabel");
            Window.Width = Clamp(saved.Width, 330, 1200, 380); Window.Height = Clamp(saved.Height, 490, 1600, 650);
            Get<RowDefinition>("NoteRow").Height = new GridLength(Clamp(saved.NoteHeight, 82, Window.Height, 136));
            Rect area = SystemParameters.WorkArea;
            Window.Left = saved.Left.HasValue && IsFinite(saved.Left.Value) ? saved.Left.Value : Math.Max(area.Left, area.Right - Window.Width - 28);
            Window.Top = saved.Top.HasValue && IsFinite(saved.Top.Value) ? saved.Top.Value : area.Top + 45;
            Window.Topmost = saved.Pinned;
            input.Text = saved.Draft; note.Text = saved.Note;
            foreach (TodoItem task in saved.Tasks) { task.Editing = false; tasks.Add(task); task.PropertyChanged += TaskChanged; }
            tasks.CollectionChanged += CollectionChanged;
            list.ItemsSource = tasks;
            input.TextChanged += delegate { UpdatePlaceholders(); QueueSave(); };
            note.TextChanged += delegate { UpdatePlaceholders(); QueueSave(); };
            input.KeyDown += delegate(object sender, KeyEventArgs e) { if (e.Key == Key.Return && !e.IsRepeat) { AddTask(); e.Handled = true; } };
            Get<Button>("AddButton").Click += delegate { AddTask(); };
            Get<Button>("PinButton").Click += delegate { TogglePin(); };
            Get<Button>("MinimizeButton").Click += delegate { Window.WindowState = WindowState.Minimized; };
            Get<Button>("CloseButton").Click += delegate { Window.Close(); };
            Get<Button>("ClearCompletedButton").Click += delegate
            {
                EndEdit(false);
                history.Delete(tasks, tasks.Where(t => t.Completed).ToList());
                UpdateCounts();
            };
            Get<Button>("UndoButton").Click += delegate { UndoDelete(); };
            Get<Border>("TitleBar").MouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs e)
            {
                if (Ancestor<ButtonBase>(e.OriginalSource as DependencyObject) == null && e.ButtonState == MouseButtonState.Pressed)
                { EndEdit(false); Window.DragMove(); }
            };
            list.AddHandler(ButtonBase.ClickEvent, new RoutedEventHandler(TaskButton));
            list.MouseDoubleClick += delegate(object sender, MouseButtonEventArgs e)
            {
                FrameworkElement source = e.OriginalSource as FrameworkElement;
                if (source is TextBlock && Convert.ToString(source.Tag) == "TaskTitle") BeginEdit(source.DataContext as TodoItem);
            };
            list.AddHandler(UIElement.LostKeyboardFocusEvent, new KeyboardFocusChangedEventHandler(EditorLostFocus));
            list.PreviewKeyDown += ListKeyDown;
            list.PreviewMouseLeftButtonDown += DragMouseDown;
            list.PreviewMouseMove += DragMouseMove;
            list.DragOver += delegate(object sender, DragEventArgs e)
            { e.Effects = e.Data.GetDataPresent(typeof(TodoItem)) ? DragDropEffects.Move : DragDropEffects.None; e.Handled = true; };
            list.Drop += DropTask;
            Window.PreviewKeyDown += WindowKeyDown;
            Window.LocationChanged += delegate { QueueSave(); };
            Window.SizeChanged += delegate { QueueSave(); };
            Get<Grid>("LayoutGrid").SizeChanged += delegate { UpdateNoteBounds(); };
            Get<RowDefinition>("NoteRow").SizeChangedSafe(QueueSave);
            Window.Closing += Closing;
            Window.Loaded += delegate
            {
                EnsureVisible(); UpdateNoteBounds(); UpdateCounts(); UpdatePin(); UpdatePlaceholders(); UpdateDate();
                ready = true;
                if (store.WriteBlocked)
                {
                    input.IsReadOnly = true; note.IsReadOnly = true; list.IsEnabled = false;
                    Get<Button>("AddButton").IsEnabled = false;
                    Get<Button>("ClearCompletedButton").IsEnabled = false;
                }
                if (store.LoadMessage != null)
                {
                    saveLabel.Text = store.WriteBlocked ? "저장 중단 · 파일 확인 필요" : "메모 복원됨 · 안내 확인";
                    saveLabel.Foreground = Brush("#A46F3E");
                }
                saveLabel.ToolTip = (store.LoadMessage == null ? "자동으로 이 PC에 저장합니다." : store.LoadMessage) + "\n" + store.FilePath;
                input.Focus();
                if (!File.Exists(store.FilePath) && !store.WriteBlocked) QueueSave();
            };
            Window.SourceInitialized += delegate
            {
                try { int round = 2; DwmSetWindowAttribute(new WindowInteropHelper(Window).Handle, 33, ref round, sizeof(int)); } catch (DllNotFoundException) { }
            };
            saveTimer.Tick += delegate { saveTimer.Stop(); SaveNow(); };
            dateTimer.Tick += delegate { UpdateDate(); };
            dateTimer.Start();
        }

        [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
        private static bool IsFinite(double x) { return !double.IsNaN(x) && !double.IsInfinity(x); }
        private static double Clamp(double value, double min, double max, double fallback)
        { return IsFinite(value) ? Math.Max(min, Math.Min(Math.Max(min, max), value)) : fallback; }

        private void UpdateNoteBounds()
        {
            Grid content = Get<Grid>("ContentGrid");
            Grid layout = Get<Grid>("LayoutGrid");
            double available = layout.ActualHeight - layout.RowDefinitions[0].ActualHeight -
                layout.RowDefinitions[2].ActualHeight - content.Margin.Top - content.Margin.Bottom;
            if (available <= 0) return;
            // Reserve room for the header, input, splitter, and usable task list/footer.
            // GridSplitter otherwise permits a pixel-sized memo row to overflow a star row.
            double reserved = content.RowDefinitions[0].ActualHeight + content.RowDefinitions[1].ActualHeight +
                content.RowDefinitions[2].ActualHeight + content.RowDefinitions[3].MinHeight + content.RowDefinitions[4].ActualHeight;
            RowDefinition row = Get<RowDefinition>("NoteRow");
            row.MaxHeight = Math.Max(row.MinHeight, available - reserved);
        }

        private void EnsureVisible()
        {
            Matrix fromDevice = PresentationSource.FromVisual(Window).CompositionTarget.TransformFromDevice;
            bool visible = false;
            Rect title = new Rect(Window.Left, Window.Top, Window.Width, 48);
            foreach (var screen in System.Windows.Forms.Screen.AllScreens)
            {
                var b = screen.WorkingArea;
                Rect screenRect = new Rect(fromDevice.Transform(new Point(b.Left, b.Top)), fromDevice.Transform(new Point(b.Right, b.Bottom)));
                Rect intersection = Rect.Intersect(title, screenRect);
                if (!intersection.IsEmpty && intersection.Width >= 100 && intersection.Height >= 28) { visible = true; break; }
            }
            if (!visible)
            {
                Rect area = SystemParameters.WorkArea;
                Window.Left = Math.Max(area.Left, area.Right - Window.Width - 28); Window.Top = area.Top + 32;
            }
        }
        private void UpdateDate() { Get<TextBlock>("DateLabel").Text = DateTime.Now.ToString("M월 d일 dddd", CultureInfo.GetCultureInfo("ko-KR")); }
        private void UpdatePlaceholders()
        {
            Get<TextBlock>("InputPlaceholder").Visibility = input.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            Get<TextBlock>("NotePlaceholder").Visibility = note.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        }
        private void UpdatePin()
        {
            Button button = Get<Button>("PinButton");
            button.Background = Brush(Window.Topmost ? "#DDE8D6" : "#E5E8E0");
            button.Foreground = Brush(Window.Topmost ? "#38634F" : "#8D9585");
            Get<TextBlock>("PinLabel").Text = Window.Topmost ? "고정" : "해제";
            AutomationProperties.SetName(button, Window.Topmost ? "항상 위 고정 켜짐" : "항상 위 고정 꺼짐");
        }
        private void TogglePin() { Window.Topmost = !Window.Topmost; UpdatePin(); QueueSave(); }
        private void UpdateCounts()
        {
            int done = tasks.Count(t => t.Completed), total = tasks.Count;
            Get<TextBlock>("CountLabel").Text = done + " / " + total;
            Get<ProgressBar>("Progress").Value = total == 0 ? 0 : (double)done / total;
            Get<StackPanel>("EmptyState").Visibility = total == 0 ? Visibility.Visible : Visibility.Collapsed;
            Get<TextBlock>("RemainingLabel").Text = total == 0 ? "적는 순간, 조금 더 가벼워져요" : (done == total ? "오늘 적은 일을 모두 마쳤어요" : (total - done) + "개의 할 일이 남았어요");
            Get<Button>("ClearCompletedButton").IsEnabled = done > 0;
            Get<Button>("UndoButton").Visibility = history.CanUndo ? Visibility.Visible : Visibility.Collapsed;
        }
        private void CollectionChanged(object sender, NotifyCollectionChangedEventArgs e)
        {
            if (e.Action != NotifyCollectionChangedAction.Move)
            {
                if (e.OldItems != null) foreach (TodoItem t in e.OldItems) t.PropertyChanged -= TaskChanged;
                if (e.NewItems != null) foreach (TodoItem t in e.NewItems) t.PropertyChanged += TaskChanged;
            }
            UpdateCounts(); QueueSave();
        }
        private void TaskChanged(object sender, PropertyChangedEventArgs e)
        { if (e.PropertyName != "Editing") { UpdateCounts(); QueueSave(); } }
        private void AddTask()
        {
            EndEdit(false);
            string text = input.Text.Trim();
            if (text.Length == 0) { input.Focus(); return; }
            TodoItem task = new TodoItem { Text = text };
            tasks.Add(task); input.Clear(); list.ScrollIntoView(task); input.Focus();
        }
        private void TaskButton(object sender, RoutedEventArgs e)
        {
            Button button = e.OriginalSource as Button;
            if (button == null) button = Ancestor<Button>(e.OriginalSource as DependencyObject);
            if (button == null) return;
            TodoItem task = button.DataContext as TodoItem;
            if (task == null) return;
            if (Convert.ToString(button.Tag) == "EditTask") { BeginEdit(task); e.Handled = true; }
            if (Convert.ToString(button.Tag) == "DeleteTask")
            { EndEdit(false); history.Delete(tasks, new[] { task }); UpdateCounts(); e.Handled = true; }
        }
        private void BeginEdit(TodoItem item)
        {
            if (item == null) return;
            EndEdit(false); editItem = item; editOriginal = item.Text; item.Editing = true;
            list.SelectedItem = item; list.ScrollIntoView(item);
            Window.Dispatcher.BeginInvoke(new Action(delegate
            {
                if (editItem != item) return;
                ListBoxItem container = list.ItemContainerGenerator.ContainerFromItem(item) as ListBoxItem;
                TextBox editor = FindChild<TextBox>(container, "TaskEditor");
                if (editor != null) { editor.Focus(); editor.SelectAll(); }
            }), DispatcherPriority.Input);
        }
        private void EndEdit(bool cancel)
        {
            if (editItem == null) return;
            TodoItem item = editItem; editItem = null;
            string text = item.Text.Trim();
            item.Text = cancel || text.Length == 0 ? editOriginal : text;
            item.Editing = false;
        }
        private void EditorLostFocus(object sender, KeyboardFocusChangedEventArgs e)
        {
            TextBox editor = e.OriginalSource as TextBox;
            if (editor != null && Convert.ToString(editor.Tag) == "TaskEditor") EndEdit(false);
        }
        private void ListKeyDown(object sender, KeyEventArgs e)
        {
            if (editItem != null && (e.Key == Key.Return || e.Key == Key.Escape))
            { EndEdit(e.Key == Key.Escape); list.Focus(); e.Handled = true; return; }
            TodoItem selected = list.SelectedItem as TodoItem;
            if (selected == null || e.OriginalSource is TextBox) return;
            if (e.Key == Key.F2) { BeginEdit(selected); e.Handled = true; }
            if (e.Key == Key.Delete) { history.Delete(tasks, new[] { selected }); UpdateCounts(); e.Handled = true; }
            if ((Keyboard.Modifiers & ModifierKeys.Alt) != 0 && (e.SystemKey == Key.Up || e.SystemKey == Key.Down || e.Key == Key.Up || e.Key == Key.Down))
            {
                bool up = e.SystemKey == Key.Up || e.Key == Key.Up;
                int index = tasks.IndexOf(selected), target = index + (up ? -1 : 1);
                if (target >= 0 && target < tasks.Count) { tasks.Move(index, target); list.ScrollIntoView(selected); }
                e.Handled = true;
            }
        }
        private void UndoDelete() { EndEdit(false); history.Undo(tasks); UpdateCounts(); }
        private void WindowKeyDown(object sender, KeyEventArgs e)
        {
            ModifierKeys modifiers = Keyboard.Modifiers;
            if (e.Key == Key.P && modifiers == (ModifierKeys.Control | ModifierKeys.Shift)) { TogglePin(); e.Handled = true; }
            if (e.Key == Key.N && modifiers == ModifierKeys.Control) { input.Focus(); e.Handled = true; }
            if (e.Key == Key.Z && modifiers == ModifierKeys.Control && Ancestor<TextBox>(e.OriginalSource as DependencyObject) == null)
            { UndoDelete(); e.Handled = true; }
        }
        private void DragMouseDown(object sender, MouseButtonEventArgs e)
        {
            FrameworkElement source = e.OriginalSource as FrameworkElement;
            dragItem = source != null && Convert.ToString(source.Tag) == "DragHandle" ? source.DataContext as TodoItem : null;
            dragStart = e.GetPosition(list);
        }
        private void DragMouseMove(object sender, MouseEventArgs e)
        {
            if (dragItem == null || e.LeftButton != MouseButtonState.Pressed) return;
            Point now = e.GetPosition(list);
            if (Math.Abs(now.X - dragStart.X) < SystemParameters.MinimumHorizontalDragDistance && Math.Abs(now.Y - dragStart.Y) < SystemParameters.MinimumVerticalDragDistance) return;
            TodoItem item = dragItem; dragItem = null;
            EndEdit(false); list.SelectedItem = item;
            DragDrop.DoDragDrop(list, new DataObject(typeof(TodoItem), item), DragDropEffects.Move);
        }
        private void DropTask(object sender, DragEventArgs e)
        {
            if (!e.Data.GetDataPresent(typeof(TodoItem))) return;
            TodoItem item = e.Data.GetData(typeof(TodoItem)) as TodoItem;
            ListBoxItem row = Ancestor<ListBoxItem>(e.OriginalSource as DependencyObject);
            TodoItem target = row == null ? null : row.DataContext as TodoItem;
            int oldIndex = tasks.IndexOf(item), newIndex = target == null ? tasks.Count - 1 : tasks.IndexOf(target);
            if (oldIndex >= 0 && newIndex >= 0 && oldIndex != newIndex) tasks.Move(oldIndex, newIndex);
            list.SelectedItem = item; e.Handled = true;
        }
        private void QueueSave()
        {
            if (!ready || store.WriteBlocked) return;
            dirty = true; saveTimer.Stop(); saveTimer.Start();
            if (saveError == null && !store.WriteBlocked) saveLabel.Text = "저장 중…";
        }
        private bool SaveNow()
        {
            if (!ready || !dirty) return true;
            saveTimer.Stop();
            try
            {
                saved.Tasks = tasks.ToList(); saved.Note = note.Text; saved.Draft = input.Text; saved.Pinned = Window.Topmost;
                if (Window.WindowState == WindowState.Normal)
                { saved.Left = Window.Left; saved.Top = Window.Top; saved.Width = Window.Width; saved.Height = Window.Height; }
                saved.NoteHeight = Get<RowDefinition>("NoteRow").ActualHeight;
                store.Save(saved); dirty = false; saveError = null;
                saveLabel.Text = "자동 저장됨 · " + DateTime.Now.ToString("HH:mm");
                saveLabel.Foreground = Brush("#8D9881");
                saveLabel.ToolTip = (store.LoadMessage == null ? "이 PC에 자동 저장했습니다." : store.LoadMessage) + "\n" + store.FilePath;
                return true;
            }
            catch (Exception e)
            {
                saveError = e.Message;
                saveLabel.Text = "저장 실패 · 안내 확인"; saveLabel.Foreground = Brush("#AC5546");
                saveLabel.ToolTip = "저장 폴더가 쓰기 가능한지 확인해 주세요.\n" + store.FilePath + "\n" + e.Message;
                return false;
            }
        }
        private void Closing(object sender, CancelEventArgs e)
        {
            EndEdit(false);
            // Preserve unsaved work on I/O errors. An untouched future-format file can close safely.
            if (dirty && !SaveNow())
            {
                e.Cancel = true;
                MessageBox.Show(Window, "메모를 저장하지 못했습니다. 창을 열어 두었습니다.\n저장 폴더의 권한이나 파일 상태를 확인한 뒤 다시 닫아 주세요.\n\n" + saveError, "곁메모 · 저장 확인", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            saveTimer.Stop(); dateTimer.Stop();
        }
        private static T Ancestor<T>(DependencyObject element) where T : DependencyObject
        {
            while (element != null)
            {
                T match = element as T; if (match != null) return match;
                element = element is Visual || element is System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(element) : LogicalTreeHelper.GetParent(element);
            }
            return null;
        }
        private static T FindChild<T>(DependencyObject parent, string name) where T : FrameworkElement
        {
            if (parent == null) return null;
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
            {
                DependencyObject child = VisualTreeHelper.GetChild(parent, i);
                T match = child as T;
                if (match != null && match.Name == name) return match;
                T nested = FindChild<T>(child, name); if (nested != null) return nested;
            }
            return null;
        }
    }

    internal static class RowDefinitionExtensions
    {
        public static void SizeChangedSafe(this RowDefinition row, Action callback)
        {
            // RowDefinition has no SizeChanged event; its Height DP changes on splitter drags.
            DependencyPropertyDescriptor.FromProperty(RowDefinition.HeightProperty, typeof(RowDefinition)).AddValueChanged(row, delegate { callback(); });
        }
    }
}
