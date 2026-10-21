# Run from the sibling log-reader-tui project directory.
Output ../blog/articles/symfony-tui/log-reader-session.gif

Require php

Set Shell "zsh"
Set FontFamily "JetBrains Mono"
Set FontSize 20
Set Width 1000
Set Height 160
Set Padding 16
Set Framerate 15
# Mocha with ANSI color 8 brightened for the list descriptions.
Set Theme { "name": "Catppuccin Mocha", "background": "#1e1e2e", "foreground": "#cdd6f4", "cursor": "#f5e0dc", "selection": "#353749", "black": "#45475a", "red": "#f38ba8", "green": "#a6e3a1", "yellow": "#f9e2af", "blue": "#89b4fa", "magenta": "#f5c2e7", "cyan": "#94e2d5", "white": "#a6adc8", "brightBlack": "#a6adc8", "brightRed": "#f38ba8", "brightGreen": "#a6e3a1", "brightYellow": "#f9e2af", "brightBlue": "#89b4fa", "brightMagenta": "#f5c2e7", "brightCyan": "#94e2d5", "brightWhite": "#bac2de" }
Set TypingSpeed 35ms
Env ZDOTDIR "."
Env DEMO_COMMAND "../blog/articles/symfony-tui/recordings/first-session.php"

Hide
Type `DEMO_BACKUP=$(mktemp)`
Enter
Type `cp src/Command/ReadLogCommand.php "$DEMO_BACKUP"`
Enter
Type `trap 'cp "$DEMO_BACKUP" src/Command/ReadLogCommand.php' EXIT`
Enter
Type `cp "$DEMO_COMMAND" src/Command/ReadLogCommand.php`
Enter
Type "export PS1='$ '"
Enter
Ctrl+L
Sleep 300ms
Show

Sleep 500ms
Type `php bin/console app:read-log`
Enter
Sleep 2s
Type "q"
Sleep 1.5s

Hide
Type `cp "$DEMO_BACKUP" src/Command/ReadLogCommand.php`
Enter
