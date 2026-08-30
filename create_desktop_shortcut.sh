#!/usr/bin/env bash
# Puts a RumbleArena launcher on the Desktop. Run once, on your own machine.
set -uo pipefail
PROJECT="$(cd "$(dirname "$0")" && pwd)"

desktop_dir() {
	if command -v xdg-user-dir >/dev/null 2>&1; then
		local dir
		dir="$(xdg-user-dir DESKTOP 2>/dev/null)"
		[ -n "$dir" ] && [ -d "$dir" ] && { echo "$dir"; return; }
	fi
	[ -d "$HOME/Desktop" ] && { echo "$HOME/Desktop"; return; }
	echo ""
}

DESKTOP="$(desktop_dir)"
if [ -z "$DESKTOP" ]; then
	echo "Could not find your Desktop folder. Is one set up?"
	exit 1
fi

case "$(uname -s)" in
Darwin)
	TARGET="$DESKTOP/RumbleArena.command"
	cat > "$TARGET" <<LAUNCHER
#!/usr/bin/env bash
# Created by RumbleArena's create_desktop_shortcut.sh
exec "$PROJECT/play.sh" "\$@"
LAUNCHER
	chmod +x "$TARGET"
	echo "Created: $TARGET"
	echo
	echo "The first time you open it, macOS may block it because it was not"
	echo "downloaded from the App Store. Right-click it and choose Open, then"
	echo "confirm -- after that a double-click works."
	;;
*)
	TARGET="$DESKTOP/RumbleArena.desktop"
	cat > "$TARGET" <<LAUNCHER
[Desktop Entry]
Type=Application
Version=1.0
Name=RumbleArena
Comment=4-player ninja arena brawler
Exec="$PROJECT/play.sh"
Path=$PROJECT
Icon=$PROJECT/icon.png
Terminal=false
Categories=Game;ActionGame;
LAUNCHER
	chmod +x "$TARGET"
	# Without this, most desktops show it as an untrusted script on first click.
	if command -v gio >/dev/null 2>&1; then
		gio set "$TARGET" metadata::trusted true 2>/dev/null || true
	fi
	echo "Created: $TARGET"
	echo
	echo "If your desktop shows it as untrusted, right-click it and choose"
	echo "'Allow Launching' (the wording varies by desktop environment)."
	;;
esac
