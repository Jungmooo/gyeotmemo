using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Threading;

internal static class LayoutRegression
{
    private static void Drag(Window window, GridSplitter splitter, double delta)
    {
        splitter.RaiseEvent(new DragStartedEventArgs(0, 0) { RoutedEvent = Thumb.DragStartedEvent });
        splitter.RaiseEvent(new DragDeltaEventArgs(0, delta) { RoutedEvent = Thumb.DragDeltaEvent });
        splitter.RaiseEvent(new DragCompletedEventArgs(0, delta, false) { RoutedEvent = Thumb.DragCompletedEvent });
        window.UpdateLayout();
    }
    private static Window OpenController(Assembly assembly, string directory)
    {
        object store = Activator.CreateInstance(assembly.GetType("GyeotMemo.MemoStore"), new object[] { directory });
        object controller = Activator.CreateInstance(assembly.GetType("GyeotMemo.MainController"), new object[] { store });
        Window window = (Window)controller.GetType().GetProperty("Window").GetValue(controller, null);
        window.Title = "곁메모 · 레이아웃 검증";
        window.ShowActivated = false; window.ShowInTaskbar = false;
        window.Show(); window.UpdateLayout();
        return window;
    }
    private static string Metrics(Window window)
    {
        var content = (Grid)window.FindName("ContentGrid");
        var layout = (Grid)window.FindName("LayoutGrid");
        var row = (RowDefinition)window.FindName("NoteRow");
        return "window=" + window.ActualHeight + ", root=" + layout.ActualHeight + ", content=" + content.ActualHeight +
            ", header=" + content.RowDefinitions[0].ActualHeight + ", progress=" + content.RowDefinitions[1].ActualHeight +
            ", input=" + content.RowDefinitions[2].ActualHeight + ", splitter=" + content.RowDefinitions[4].ActualHeight +
            ", memo max=" + row.MaxHeight + ", requested=" + row.Height;
    }
    private static T Find<T>(DependencyObject parent) where T : DependencyObject
    {
        if (parent is T) return (T)parent;
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        { T found = Find<T>(VisualTreeHelper.GetChild(parent, i)); if (found != null) return found; }
        return null;
    }
    [STAThread]
    private static int Main(string[] args)
    {
        var lines = new List<string>();
        Window window = null;
        try
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            Assembly assembly = Assembly.LoadFrom(args[0]);
            using (Stream resource = assembly.GetManifestResourceStream("MainWindow.xaml"))
                window = (Window)XamlReader.Load(resource);
            window.Title = "곁메모 · 레이아웃 검증";
            window.ShowActivated = false; window.ShowInTaskbar = false;
            window.Show(); window.UpdateLayout();
            var splitter = Find<GridSplitter>(window);
            var note = (TextBox)window.FindName("NoteInput");
            var noteRow = (RowDefinition)window.FindName("NoteRow");
            var footer = (Button)window.FindName("ClearCompletedButton");
            double beforeRow = noteRow.ActualHeight, beforeInput = note.ActualHeight;
            double beforeFooter = ((FrameworkElement)footer.Parent).ActualHeight;
            double beforeWindow = window.ActualHeight;
            lines.Add("Before: memo row=" + beforeRow + ", input=" + beforeInput + ", footer=" + beforeFooter);
            // Exercise the actual WPF GridSplitter handlers, not a duplicate resizing algorithm.
            splitter.RaiseEvent(new DragStartedEventArgs(0, 0) { RoutedEvent = Thumb.DragStartedEvent });
            splitter.RaiseEvent(new DragDeltaEventArgs(0, -100) { RoutedEvent = Thumb.DragDeltaEvent });
            window.UpdateLayout();
            lines.Add("During drag: memo input=" + note.ActualHeight);
            splitter.RaiseEvent(new DragCompletedEventArgs(0, -100, false) { RoutedEvent = Thumb.DragCompletedEvent });
            window.UpdateLayout();
            lines.Add("After: memo row=" + noteRow.ActualHeight + ", input=" + note.ActualHeight + ", footer=" + ((FrameworkElement)footer.Parent).ActualHeight);
            if (noteRow.ActualHeight < beforeRow + 80 || note.ActualHeight < beforeInput + 80)
                throw new Exception("Dragging upward did not enlarge the actual memo input.");
            if (Math.Abs(((FrameworkElement)footer.Parent).ActualHeight - beforeFooter) > 1)
                throw new Exception("Dragging changed the footer height instead of redistributing list/memo space.");
            if (Math.Abs(window.ActualHeight - beforeWindow) > 1)
                throw new Exception("Splitter changed the outer window size.");
            lines.Add("PASS: actual memo input grows by 100px while footer and window heights stay fixed.");
            splitter.RaiseEvent(new DragStartedEventArgs(0, 0) { RoutedEvent = Thumb.DragStartedEvent });
            splitter.RaiseEvent(new DragDeltaEventArgs(0, 60) { RoutedEvent = Thumb.DragDeltaEvent });
            splitter.RaiseEvent(new DragCompletedEventArgs(0, 60, false) { RoutedEvent = Thumb.DragCompletedEvent });
            window.UpdateLayout();
            if (Math.Abs(noteRow.ActualHeight - (beforeRow + 40)) > 2)
                throw new Exception("Downward drag did not shrink the actual memo input by 60px.");
            lines.Add("PASS: downward drag shrinks the memo input by 60px.");
            window.Close(); window = null;

            string directory = Path.Combine(Path.GetDirectoryName(args[1]), "layout-data-" + Guid.NewGuid().ToString("N"));
            window = OpenController(assembly, directory);
            ((TextBox)window.FindName("NoteInput")).Text = "메모 크기 복원 검증\r\n두 번째 줄";
            splitter = Find<GridSplitter>(window);
            Drag(window, splitter, -10000);
            double enlarged = ((RowDefinition)window.FindName("NoteRow")).ActualHeight;
            lines.Add("Largest memo row before restart=" + enlarged);
            lines.Add("Largest metrics: " + Metrics(window));
            window.Close(); window = OpenController(assembly, directory);
            double restored = ((RowDefinition)window.FindName("NoteRow")).ActualHeight;
            lines.Add("Restored memo row=" + restored);
            lines.Add("Restored metrics: " + Metrics(window));
            if (Math.Abs(restored - enlarged) > 1)
                throw new Exception("Restart did not preserve the enlarged memo area height.");
            if (((TextBox)window.FindName("NoteInput")).Text != "메모 크기 복원 검증\r\n두 번째 줄")
                throw new Exception("Memo contents changed while restoring layout.");
            lines.Add("PASS: enlarged memo area and multi-line contents survive restart.");
            window.Height = window.MinHeight;
            // WPF delivers native window resize and SizeChanged notifications on the dispatcher.
            var frame = new DispatcherFrame();
            window.Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(delegate { frame.Continue = false; }));
            Dispatcher.PushFrame(frame);
            window.UpdateLayout();
            lines.Add("After Height setter: requested=" + window.Height + ", actual=" + window.ActualHeight + ", content=" + ((Grid)window.FindName("ContentGrid")).ActualHeight + ", memo max=" + ((RowDefinition)window.FindName("NoteRow")).MaxHeight);
            note = (TextBox)window.FindName("NoteInput");
            double bottom = note.TranslatePoint(new Point(0, note.ActualHeight), window).Y;
            double statusTop = ((TextBlock)window.FindName("SaveLabel")).TranslatePoint(new Point(), window).Y;
            lines.Add("Minimum window: memo bottom=" + bottom + ", status top=" + statusTop);
            if (bottom > statusTop || note.ActualHeight < 35)
                throw new Exception("Memo input overflows or becomes unusable after shrinking the outer window.");
            lines.Add("PASS: memo area remains inside the minimum-sized window.");
            File.WriteAllLines(args[1], lines, new UTF8Encoding(false));
            return 0;
        }
        catch (Exception error)
        { lines.Add("FAIL: " + error); File.WriteAllLines(args[1], lines, new UTF8Encoding(false)); return 1; }
        finally { if (window != null) window.Close(); }
    }
}
