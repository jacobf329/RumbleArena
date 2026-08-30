#!/usr/bin/env bash
# Puts the RumbleArena launcher and updater on the Desktop. Run once, on your
# own machine. The updater gets its own icon because a notice you have to go
# hunting through a folder to act on is a notice most people ignore.
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

	UPDATER="$DESKTOP/Update RumbleArena.command"
	cat > "$UPDATER" <<UPDATE
#!/usr/bin/env bash
# Created by RumbleArena's create_desktop_shortcut.sh
"$PROJECT/update.sh" "\$@"
echo
echo "Press return to close."
read -r _
UPDATE
	chmod +x "$UPDATER"
	echo "Created: $UPDATER"
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
	UPDATER="$DESKTOP/Update RumbleArena.desktop"
	cat > "$UPDATER" <<UPDATE
[Desktop Entry]
Type=Application
Version=1.0
Name=Update RumbleArena
Comment=Download the latest version of RumbleArena
Exec="$PROJECT/update.sh"
Path=$PROJECT
Icon=$PROJECT/icon.png
Terminal=true
Categories=Game;
UPDATE
	chmod +x "$UPDATER"
	# Without this, most desktops show these as untrusted scripts on first click.
	if command -v gio >/dev/null 2>&1; then
		gio set "$TARGET" metadata::trusted true 2>/dev/null || true
		gio set "$UPDATER" metadata::trusted true 2>/dev/null || true
	fi
	echo "Created: $TARGET"
	echo "Created: $UPDATER"
	echo
	echo "If your desktop shows it as untrusted, right-click it and choose"
	echo "'Allow Launching' (the wording varies by desktop environment)."
	;;
esac
