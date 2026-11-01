# GUI session tweaks for Electron inside the instance.
# Sourced by antigravity-app and antigravity-ide.

# ThinLinc exports DBUS_SESSION_BUS_ADDRESS. On this image the host session
# bus has both mate and plasma service files for org.freedesktop.Notifications,
# so activation runs plasma_waitforname and libnotify blocks the UI until the
# dbus timeout (~25s) on every notification. A socket that is never created
# fails the connect immediately and does not autolaunch a bus.
agy_prepare_gui_session() {
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/tmp/agy-no-session-bus-${UID}"
  unset DBUS_SESSION_BUS_PID || true

  # chrome-sandbox in the unpacked tree is mode 4755 owned by the user, not
  # root, so Chromium's setuid sandbox cannot work. It also strips LD_PRELOAD
  # on re-exec. Stay unsandboxed so the MIT-SHM guard below stays loaded.
  export ELECTRON_DISABLE_SANDBOX=1

  local noshm="/opt/agy-stack/host-scripts/libnoshm.so"
  if [[ -f "$noshm" ]]; then
    case ":${LD_PRELOAD:-}:" in
      *":$noshm:"*) ;;
      *) export LD_PRELOAD="${noshm}${LD_PRELOAD:+:$LD_PRELOAD}" ;;
    esac
  fi
}
