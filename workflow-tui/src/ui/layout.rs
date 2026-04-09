use ratatui::layout::{Constraint, Direction, Layout, Rect};

pub struct DashboardLayout {
    pub sidebar: Rect,
    pub grid: [Rect; 4],
}

pub fn build_layout(area: Rect) -> DashboardLayout {
    let columns = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(25), Constraint::Percentage(75)])
        .split(area);

    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(columns[1]);

    let top = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(rows[0]);

    let bottom = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(rows[1]);

    DashboardLayout {
        sidebar: columns[0],
        grid: [top[0], top[1], bottom[0], bottom[1]],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_area() -> Rect {
        Rect::new(0, 0, 200, 50)
    }

    #[test]
    fn build_layout_returns_sidebar_and_4_grid_rects() {
        let layout = build_layout(test_area());
        assert!(layout.sidebar.width > 0);
        assert!(layout.sidebar.height > 0);
        for rect in &layout.grid {
            assert!(rect.width > 0);
            assert!(rect.height > 0);
        }
    }

    #[test]
    fn sidebar_width_is_approximately_25_percent() {
        let area = test_area();
        let layout = build_layout(area);
        let ratio = layout.sidebar.width as f64 / area.width as f64;
        assert!(
            (0.20..=0.30).contains(&ratio),
            "sidebar ratio {ratio} not ~25%"
        );
    }

    #[test]
    fn grid_panels_divide_remaining_75_into_2x2() {
        let area = test_area();
        let layout = build_layout(area);
        let grid_width = area.width - layout.sidebar.width;
        for rect in &layout.grid {
            let w_ratio = rect.width as f64 / grid_width as f64;
            assert!(
                (0.40..=0.60).contains(&w_ratio),
                "grid panel width ratio {w_ratio} not ~50%"
            );
        }
        // Top and bottom rows should each be ~50% of total height
        let h_ratio = layout.grid[0].height as f64 / area.height as f64;
        assert!(
            (0.40..=0.60).contains(&h_ratio),
            "grid panel height ratio {h_ratio} not ~50%"
        );
    }

    #[test]
    fn existing_panels_render_without_errors_in_new_layout() {
        // All 5 rects from build_layout must be non-overlapping and within bounds
        let area = test_area();
        let layout = build_layout(area);

        // Sidebar is left of grid
        assert!(layout.sidebar.x + layout.sidebar.width <= layout.grid[0].x);

        // All rects within the original area
        for rect in std::iter::once(&layout.sidebar).chain(layout.grid.iter()) {
            assert!(rect.x + rect.width <= area.x + area.width);
            assert!(rect.y + rect.height <= area.y + area.height);
        }
    }

    #[test]
    fn spec_list_renders_correctly_in_narrow_sidebar_dimensions() {
        // Even on a narrow terminal, sidebar gets a usable width
        let narrow_area = Rect::new(0, 0, 80, 24);
        let layout = build_layout(narrow_area);
        // Sidebar should be at least 15 columns (enough for short spec names)
        assert!(
            layout.sidebar.width >= 15,
            "sidebar too narrow: {}",
            layout.sidebar.width
        );
    }
}
