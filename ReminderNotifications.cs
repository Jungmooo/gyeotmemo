using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;

namespace GyeotMemo
{
    internal sealed class ReminderNotifications : IDisposable
    {
        private readonly NotifyIcon tray;
        private readonly Icon icon;
        private readonly ContextMenuStrip menu;
        public event EventHandler Shown;

        public ReminderNotifications(Action openWindow, Action closeWindow)
        {
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ico"))
            using (Icon embedded = new Icon(stream))
                icon = (Icon)embedded.Clone();
            menu = new ContextMenuStrip();
            menu.Items.Add("곁메모 열기", null, delegate { openWindow(); });
            menu.Items.Add("종료", null, delegate { closeWindow(); });
            tray = new NotifyIcon { Icon = icon, Text = "곁메모 · 일정 30분 전 알림", ContextMenuStrip = menu, Visible = true };
            tray.DoubleClick += delegate { openWindow(); };
            tray.BalloonTipClicked += delegate { openWindow(); };
            tray.BalloonTipShown += delegate { if (Shown != null) Shown(this, EventArgs.Empty); };
        }

        public void Show(IList<TodoItem> items, DateTime now)
        {
            string text;
            if (items.Count == 1)
            {
                TodoItem item = items[0];
                int minutes = Math.Max(1, (int)Math.Ceiling((item.DueAt.Value - now).TotalMinutes));
                text = minutes + "분 후 · " + item.DueAt.Value.ToString("M월 d일 HH:mm") + "\n" + item.Text;
            }
            else
            {
                text = string.Join("\n", items.Take(3).Select(item => item.DueAt.Value.ToString("HH:mm") + " · " + item.Text));
                if (items.Count > 3) text += "\n외 " + (items.Count - 3) + "개 일정";
            }
            ShowMessage("곁메모 · 일정 알림", text);
        }

        public void ShowTest()
        {
            ShowMessage("곁메모 · 알림 테스트", "알림이 정상적으로 도착했어요.\n날짜와 시간을 적은 할 일은 30분 전에 알려드려요.");
        }

        private void ShowMessage(string title, string text)
        {
            if (text.Length > 240) text = text.Substring(0, 239) + "…";
            // The Windows shell renders this in its native notification UI, without activating our window.
            tray.ShowBalloonTip(10000, title, text, ToolTipIcon.None);
        }

        public void Dispose()
        {
            tray.Visible = false;
            tray.Dispose();
            menu.Dispose();
            icon.Dispose();
        }
    }
}
