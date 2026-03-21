use anyhow::Result;
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyModifiers};
use std::time::Duration;

pub enum AppEvent {
    Quit,
    NextPanel,
    PrevPanel,
    ScrollDown,
    ScrollUp,
    Select,
    Rescan,
    None,
}

pub fn poll_event(timeout: Duration) -> Result<AppEvent> {
    if !event::poll(timeout)? {
        return Ok(AppEvent::None);
    }

    let evt = match event::read()? {
        Event::Key(key) => map_key(key),
        _ => AppEvent::None,
    };

    Ok(evt)
}

fn map_key(key: KeyEvent) -> AppEvent {
    match key.code {
        KeyCode::Char('q') | KeyCode::Esc => AppEvent::Quit,
        KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => AppEvent::Quit,
        KeyCode::Tab => {
            if key.modifiers.contains(KeyModifiers::SHIFT) {
                AppEvent::PrevPanel
            } else {
                AppEvent::NextPanel
            }
        }
        KeyCode::BackTab => AppEvent::PrevPanel,
        KeyCode::Char('j') | KeyCode::Down => AppEvent::ScrollDown,
        KeyCode::Char('k') | KeyCode::Up => AppEvent::ScrollUp,
        KeyCode::Enter => AppEvent::Select,
        KeyCode::Char('r') => AppEvent::Rescan,
        _ => AppEvent::None,
    }
}
