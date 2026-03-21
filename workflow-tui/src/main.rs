mod app;
mod event;
mod model;
mod parse;
mod ui;
mod watcher;

use anyhow::{bail, Result};
use app::App;
use clap::Parser;
use crossterm::event::{DisableMouseCapture, EnableMouseCapture};
use crossterm::execute;
use crossterm::terminal::{
    EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode,
};
use event::{AppEvent, poll_event};
use std::io;
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Duration;

#[derive(Parser)]
#[command(name = "workflow-tui", about = "Terminal dashboard for spec-driven workflows")]
struct Cli {
    /// Path to the project root (must contain specs/ directory)
    #[arg(default_value = ".")]
    path: PathBuf,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let root = cli.path.canonicalize()?;

    if !root.join("specs").is_dir() {
        bail!(
            "specs/ directory not found at {}. Run from a project root or pass the path.",
            root.display()
        );
    }

    let mut app = App::new(root.clone());

    // Start file watcher (degrade gracefully if it fails)
    let watcher_rx: Option<mpsc::Receiver<()>>;
    let _watcher_guard;
    match watcher::start_watcher(&root) {
        Ok((rx, guard)) => {
            watcher_rx = Some(rx);
            _watcher_guard = Some(guard);
        }
        Err(e) => {
            eprintln!("Warning: file watcher failed ({e}), use 'r' to refresh manually");
            watcher_rx = None;
            _watcher_guard = None;
        }
    }

    // Install panic hook to restore terminal on panic
    let original_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture);
        original_hook(info);
    }));

    // Terminal setup
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = ratatui::backend::CrosstermBackend::new(stdout);
    let mut terminal = ratatui::Terminal::new(backend)?;

    let result = run_loop(&mut terminal, &mut app, &watcher_rx);

    // Restore terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    result
}

fn run_loop(
    terminal: &mut ratatui::Terminal<ratatui::backend::CrosstermBackend<io::Stdout>>,
    app: &mut App,
    watcher_rx: &Option<mpsc::Receiver<()>>,
) -> Result<()> {
    loop {
        terminal.draw(|frame| ui::render(frame, app))?;

        match poll_event(Duration::from_millis(50))? {
            AppEvent::Quit => {
                app.should_quit = true;
                break;
            }
            AppEvent::NextPanel => app.next_panel(),
            AppEvent::PrevPanel => app.prev_panel(),
            AppEvent::ScrollDown => app.scroll_down(),
            AppEvent::ScrollUp => app.scroll_up(),
            AppEvent::Select => app.select_spec(),
            AppEvent::Rescan => app.rescan(),
            AppEvent::None => {}
        }

        if let Some(rx) = watcher_rx {
            if rx.try_recv().is_ok() {
                app.rescan();
            }
        }
    }
    Ok(())
}
