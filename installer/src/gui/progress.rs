// Progress control messages are transitions, not periodic repaint requests.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Display {
    #[default]
    Idle,
    Marquee,
    Counted {
        done: u32,
        total: u32,
    },
}

impl Display {
    pub fn counted(done: u64, total: u64) -> Self {
        if total == 0 {
            return Self::Marquee;
        }
        let maximum = total.min(i32::MAX as u64) as u32;
        let position =
            (u128::from(done.min(total)) * u128::from(maximum) / u128::from(total)) as u32;
        Self::Counted {
            done: position,
            total: maximum,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    StopMarquee,
    StartMarquee,
    Range(u32),
    Position(u32),
}

#[derive(Default)]
pub struct Progress {
    display: Display,
}

impl Progress {
    pub fn update(&mut self, display: Display) -> Vec<Command> {
        let mut commands = Vec::new();
        if self.display == display {
            return commands;
        }
        if self.display == Display::Marquee {
            commands.push(Command::StopMarquee);
        }
        match display {
            Display::Marquee => commands.push(Command::StartMarquee),
            Display::Counted { done, total } => {
                if !matches!(self.display, Display::Counted { total: old, .. } if old == total) {
                    commands.push(Command::Range(total));
                }
                if !matches!(self.display, Display::Counted { done: old, total: old_total } if old == done && old_total == total)
                {
                    commands.push(Command::Position(done));
                }
            }
            Display::Idle => {}
        }
        self.display = display;
        commands
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_work_starts_animation_once_across_repeated_polls() {
        let mut progress = Progress::default();
        assert_eq!(progress.update(Display::Marquee), [Command::StartMarquee]);
        for _ in 0..30 {
            assert!(progress.update(Display::Marquee).is_empty());
        }
        assert_eq!(progress.update(Display::Idle), [Command::StopMarquee]);
        assert!(progress.update(Display::Idle).is_empty());
        assert_eq!(progress.update(Display::Marquee), [Command::StartMarquee]);
    }

    #[test]
    fn count_changes_only_move_position_and_identical_polls_send_nothing() {
        let mut progress = Progress::default();
        progress.update(Display::Marquee);
        assert_eq!(
            progress.update(Display::counted(403, 2290)),
            [
                Command::StopMarquee,
                Command::Range(2290),
                Command::Position(403)
            ]
        );
        for done in 404..420 {
            assert_eq!(
                progress.update(Display::counted(done, 2290)),
                [Command::Position(done as u32)]
            );
            assert!(progress.update(Display::counted(done, 2290)).is_empty());
        }
    }

    #[test]
    fn new_stage_range_completion_and_unknown_work_are_real_transitions() {
        let mut progress = Progress::default();
        progress.update(Display::counted(2290, 2290));
        assert_eq!(
            progress.update(Display::counted(1, 7)),
            [Command::Range(7), Command::Position(1)]
        );
        assert_eq!(progress.update(Display::Marquee), [Command::StartMarquee]);
        assert_eq!(
            progress.update(Display::counted(100, 100)),
            [
                Command::StopMarquee,
                Command::Range(100),
                Command::Position(100)
            ]
        );
        assert!(progress.update(Display::counted(100, 100)).is_empty());
    }

    #[test]
    fn zero_total_is_unknown_and_large_counts_preserve_the_ratio() {
        assert_eq!(Display::counted(0, 0), Display::Marquee);
        assert_eq!(
            Display::counted(8, 7),
            Display::Counted { done: 7, total: 7 }
        );
        assert_eq!(
            Display::counted(u64::MAX / 2, u64::MAX),
            Display::Counted {
                done: i32::MAX as u32 / 2,
                total: i32::MAX as u32
            }
        );
        assert_eq!(
            Display::counted(u64::MAX, u64::MAX),
            Display::Counted {
                done: i32::MAX as u32,
                total: i32::MAX as u32
            }
        );
    }
}
