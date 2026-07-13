using Liftoff.App.Controls;
using Liftoff.App.Services;
using Liftoff.Core.Models;
using Liftoff.Core.Protocol;
using Liftoff.Core.Pty;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage.Pickers;

namespace Liftoff.App;

public sealed partial class MainWindow : Window
{
    private readonly AppStore _store = AppStore.Shared;
    private readonly string _shell = PtySession.DefaultShell();
    private CompanionServer? _server;

    public MainWindow()
    {
        InitializeComponent();
        Title = "Liftoff";

        StartCompanionServer();

        // Open the user's home folder as a first project so there's a terminal
        // to look at on launch.
        AddProject(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
    }

    private void StartCompanionServer()
    {
        // TODO(roadmap): persist token/web-password in Windows Credential Manager;
        // surface the pairing QR in a settings pane. Generated per launch for now.
        var token = Liftoff.Core.Crypto.LiftoffCrypto.GenerateToken();
        var webPassword = "";
        var host = new AppSessionHost(_store, DispatcherQueue.GetForCurrentThread());
        _server = new CompanionServer(host, () => token, () => webPassword);
        _server.Start();
    }

    // MARK: projects

    private async void OnAddProject(object sender, RoutedEventArgs e)
    {
        var picker = new FolderPicker();
        picker.FileTypeFilter.Add("*");
        // Unpackaged apps must associate the picker with the window's HWND.
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

        var folder = await picker.PickSingleFolderAsync();
        if (folder != null) AddProject(folder.Path);
    }

    private void AddProject(string path)
    {
        var project = _store.AddProject(path);
        if (!ProjectListContains(project))
            ProjectList.Items.Add(new ListViewItem { Content = project.Name, Tag = project.Id });
        SelectProject(project);
        if (project.Terminals.Count == 0) NewTerminal(project);
    }

    private bool ProjectListContains(Project project) =>
        ProjectList.Items.OfType<ListViewItem>().Any(i => (Guid)i.Tag == project.Id);

    private void SelectProject(Project project)
    {
        _store.ActiveProjectId = project.Id;
        var item = ProjectList.Items.OfType<ListViewItem>().FirstOrDefault(i => (Guid)i.Tag == project.Id);
        if (item != null) ProjectList.SelectedItem = item;
        ReloadTerminals(project);
    }

    private void OnProjectSelected(object sender, SelectionChangedEventArgs e)
    {
        if (ProjectList.SelectedItem is ListViewItem item && item.Tag is Guid id)
        {
            var project = _store.FindProject(id);
            if (project != null) { _store.ActiveProjectId = id; ReloadTerminals(project); }
        }
    }

    // MARK: terminals

    private void ReloadTerminals(Project project)
    {
        Terminals.TabItems.Clear();
        foreach (var term in project.Terminals)
            Terminals.TabItems.Add(BuildTab(term));
        if (Terminals.TabItems.Count > 0) Terminals.SelectedIndex = 0;
    }

    private void OnAddTerminal(TabView sender, object args)
    {
        if (_store.ActiveProject is Project project) NewTerminal(project);
    }

    private void NewTerminal(Project project)
    {
        var term = project.AddTerminal(_shell);
        var tab = BuildTab(term);
        Terminals.TabItems.Add(tab);
        Terminals.SelectedItem = tab;
    }

    private TabViewItem BuildTab(TerminalSession term)
    {
        var view = new TerminalView();
        view.Attach(term);
        var tab = new TabViewItem { Header = term.DisplayTitle, Content = view, Tag = term.Id };
        return tab;
    }

    private void OnCloseTerminal(TabView sender, TabViewTabCloseRequestedEventArgs args)
    {
        if (args.Tab.Tag is not Guid id) return;
        if (args.Tab.Content is TerminalView view) view.Detach();

        foreach (var project in _store.Projects)
        {
            var term = project.Terminals.FirstOrDefault(t => t.Id == id);
            if (term != null) { project.CloseTerminal(term); break; }
        }
        sender.TabItems.Remove(args.Tab);
    }
}
