#!/bin/bash
# Installer for chargectl.
set -eu

PROG=${0##*/}
SRC=$(cd "$(dirname "$0")" && pwd)/chargectl
BIN=/usr/local/bin/chargectl
UNIT=/etc/systemd/system/chargectl.service
CONF=/etc/chargectl.conf
OLD_UNIT=/etc/systemd/system/battery-limit.service
MARKER='# chargectl: battery charge control utility'
UNIT_MARKER='# chargectl: managed by install.sh'

die()  { echo "$PROG: $*" >&2; exit 1; }
warn() { echo "$PROG: warning: $*" >&2; }
info() { echo "$*"; }

usage() {
  cat <<EOF
Usage: sudo $PROG [--force]
  or:  sudo $PROG --uninstall

Install chargectl to $BIN and enable the boot service that
re-applies the thresholds saved with 'chargectl START STOP --persist'.

  --force       replace an existing '$BIN' that was not
                installed by this script (a backup is made)
  --uninstall   remove chargectl, its service and the saved thresholds,
                and reset the battery to normal (charging enabled,
                thresholds 0% to 100%)
  -h, --help    display this help and exit
EOF
}

MODE=install
FORCE=no

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --force) FORCE=yes; shift ;;
    --uninstall) MODE=uninstall; shift ;;
    *)
      echo "$PROG: unrecognized option '$1'" >&2
      echo "Try '$PROG --help' for more information." >&2
      exit 1
      ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "must be run as root (try: sudo $PROG ...)"

have_systemd() { command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; }

do_install() {
  [ -f "$SRC" ] || die "cannot find '$SRC' (keep install.sh next to chargectl)"
  grep -qF "$MARKER" "$SRC" || die "'$SRC' does not look like chargectl"
  bash -n "$SRC" || die "'$SRC' has a syntax error"

  # Hardware check: refuse to install something that cannot work.
  found=no
  for b in /sys/class/power_supply/BAT*; do
    if [ -e "$b/charge_control_end_threshold" ]; then
      found=yes
    fi
  done
  if [ "$found" = no ] && [ "$FORCE" = no ]; then
    die "no battery with 'charge_control_end_threshold' found: charge limits are not supported on this machine (use --force to install anyway)"
  fi

  # Never overwrite a file we did not install.
  if [ -e "$BIN" ] && ! grep -qF "$MARKER" "$BIN" 2>/dev/null; then
    [ "$FORCE" = yes ] ||
      die "'$BIN' already exists and was not installed by this script (use --force to back it up and replace it)"
    backup="$BIN.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$BIN" "$backup"
    info "backed up '$BIN' to '$backup'"
  fi

  if [ -e "$UNIT" ] && ! grep -qF "$UNIT_MARKER" "$UNIT"; then
    die "'$UNIT' already exists and was not created by this script"
  fi

  # Atomic install: write a temporary file, then rename it into place.
  tmp=$(mktemp "$BIN.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  install -m 0755 -o root -g root "$SRC" "$tmp"
  mv -f "$tmp" "$BIN"
  trap - EXIT
  info "installed '$BIN'"

  if ! have_systemd; then
    warn "systemd is not running: the boot service was not installed, so --persist will not work"
    info "done. Try: chargectl status"
    return
  fi

  if systemctl is-active --quiet tlp 2>/dev/null; then
    warn "TLP is active and may overwrite the thresholds at boot (see README.md)"
  fi
  if [ -e "$OLD_UNIT" ]; then
    warn "'$OLD_UNIT' exists (manual setup); disable it to avoid conflicts: systemctl disable --now battery-limit.service"
  fi

  # Migrate thresholds from a service made by an older version of this installer.
  if [ -e "$UNIT" ] && [ ! -e "$CONF" ]; then
    old=$(sed -n 's/^ExecStart=.* \([0-9]\{1,3\}\) \([0-9]\{1,3\}\)$/\1 \2/p' "$UNIT" | head -n 1)
    if [ -n "$old" ]; then
      # shellcheck disable=SC2086
      set -- $old
      if "$BIN" "$1" "$2" --persist 2>/dev/null; then
        info "kept your previous boot thresholds: $1 and $2"
      else
        warn "could not keep your previous boot thresholds ($1 and $2); set them again with --persist"
      fi
    fi
  fi

  # The service has no numbers in it: it runs 'chargectl restore' at boot,
  # which applies the thresholds saved in $CONF (nothing, if none).
  tmp=$(mktemp "$UNIT.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  cat > "$tmp" <<EOF
$UNIT_MARKER
[Unit]
Description=Restore saved battery charge thresholds
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$BIN restore

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$tmp"
  mv -f "$tmp" "$UNIT"
  trap - EXIT

  systemctl daemon-reload
  systemctl enable --now chargectl.service
  info "enabled chargectl.service"
  info "done. Set your limit with: sudo chargectl 75 80 --persist"
}

do_uninstall() {
  if [ -e "$UNIT" ]; then
    grep -qF "$UNIT_MARKER" "$UNIT" ||
      die "'$UNIT' was not created by this script; not removing it"
    if have_systemd; then
      systemctl disable --now chargectl.service || true
    fi
    rm -f "$UNIT"
    if have_systemd; then
      systemctl daemon-reload
    fi
    info "removed '$UNIT'"
  fi

  if [ -e "$CONF" ]; then
    rm -f "$CONF"
    info "removed '$CONF'"
  fi

  if [ -e "$BIN" ]; then
    grep -qF "$MARKER" "$BIN" ||
      die "'$BIN' was not installed by this script; not removing it"
    # Leave the battery in its normal state; ignore unsupported features.
    "$BIN" enable 2>/dev/null || true
    "$BIN" 0 100 2>/dev/null || true
    rm -f "$BIN"
    info "removed '$BIN' (battery reset to normal where supported)"
  else
    info "'$BIN' is not installed"
  fi
}

if [ "$MODE" = uninstall ]; then
  do_uninstall
else
  do_install
fi
