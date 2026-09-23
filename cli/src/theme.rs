use std::io::IsTerminal;

use owo_colors::{OwoColorize, Rgb};

const AMBER: Rgb = Rgb(0xf5, 0xc5, 0x42);
const GREEN: Rgb = Rgb(0x4a, 0xde, 0x80);
const RED: Rgb = Rgb(0xf8, 0x71, 0x71);
const MUTED: Rgb = Rgb(0x8b, 0x92, 0xa5);

pub struct Theme {
    pub enabled: bool,
}

impl Theme {
    /// TTY + NO_COLOR + FORCE_COLOR aware. Pass `--no-color` via `with_overrides`.
    #[allow(dead_code)]
    pub fn detect() -> Self {
        let no_color = std::env::var_os("NO_COLOR").is_some();
        let force = std::env::var_os("FORCE_COLOR").is_some();
        let tty = std::io::stdout().is_terminal();
        let enabled = force || (!no_color && tty);
        Self { enabled }
    }

    pub fn with_overrides(disable: bool, force: bool) -> Self {
        // Priority: --no-color beats everything; FORCE_COLOR/--color forces on;
        // otherwise fall back to TTY-aware detection so a normal terminal still
        // gets colours without having to set FORCE_COLOR=1.
        if disable {
            return Self { enabled: false };
        }
        if force {
            return Self { enabled: true };
        }
        Self::detect()
    }

    pub fn accent(&self, s: &str) -> String {
        if self.enabled {
            s.color(AMBER).to_string()
        } else {
            s.to_string()
        }
    }

    pub fn success(&self, s: &str) -> String {
        if self.enabled {
            s.color(GREEN).to_string()
        } else {
            s.to_string()
        }
    }

    pub fn error(&self, s: &str) -> String {
        if self.enabled {
            s.color(RED).to_string()
        } else {
            s.to_string()
        }
    }

    pub fn muted(&self, s: &str) -> String {
        if self.enabled {
            s.color(MUTED).to_string()
        } else {
            s.to_string()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disabled_when_no_color_set() {
        std::env::set_var("NO_COLOR", "1");
        let t = Theme::detect();
        assert!(!t.enabled);
        std::env::remove_var("NO_COLOR");
    }

    #[test]
    fn explicit_disable_overrides_force() {
        let t = Theme::with_overrides(true, false);
        assert!(!t.enabled);
    }

    #[test]
    fn force_enables_even_without_tty() {
        let t = Theme::with_overrides(false, true);
        assert!(t.enabled);
    }

    #[test]
    fn disable_beats_force() {
        // --no-color always wins, regardless of force flag.
        let t = Theme::with_overrides(true, true);
        assert!(!t.enabled);
    }

    #[test]
    fn neither_flag_falls_back_to_detect() {
        // When no flags are set, with_overrides must call detect() — result
        // matches detect() output (same TTY state during test).
        let t_override = Theme::with_overrides(false, false);
        let t_detect = Theme::detect();
        assert_eq!(t_override.enabled, t_detect.enabled);
    }
}
