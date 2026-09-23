use indicatif::{ProgressBar, ProgressStyle};

const PROGRESS_THRESHOLD: usize = 1024 * 1024; // 1 MiB

/// Returns a configured `ProgressBar` when the upload is large enough to
/// warrant showing one. Returns `None` when `enabled` is false or when
/// `total < PROGRESS_THRESHOLD` (1 MiB).
pub fn maybe_bar(total: usize, label: &str, enabled: bool) -> Option<ProgressBar> {
    if !enabled || total < PROGRESS_THRESHOLD {
        return None;
    }
    let pb = ProgressBar::new(total as u64);
    pb.set_style(
        ProgressStyle::with_template(&format!(
            "  {{spinner}} {} {{bar:30}} {{bytes}}/{{total_bytes}} ({{eta}})",
            label
        ))
        .unwrap()
        .tick_chars("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏ "),
    );
    Some(pb)
}
