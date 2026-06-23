#!/bin/bash
# GlobalProtect VPN CLI controller
# Usage: gp.sh [connect|disconnect|status|toggle|set-password]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/gp.conf"

if [[ ! -f "$CONF" ]]; then
    echo "Config not found: $CONF" >&2
    exit 1
fi

# shellcheck source=gp.conf
source "$CONF"

KEYCHAIN_SERVICE="GlobalProtect/$PORTAL"
KEYCHAIN_ACCOUNT="$USERNAME"

is_gp_running() {
    pgrep -x "GlobalProtect" &>/dev/null
}

_get_password() {
    security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null
}

_is_url_reachable() {
    curl -sk --max-time 3 --output /dev/null --write-out "%{http_code}" "$1" 2>/dev/null | grep -qvE '^(000)$'
}

_wait_and_open() {
    local check_url="$1"
    local open_url="$2"
    local timeout="$3"
    local elapsed=0

    echo -n "Waiting for VPN tunnel"
    while ! _is_url_reachable "$check_url"; do
        if (( elapsed >= timeout )); then
            echo ""
            echo "Timeout after ${timeout}s — ${check_url} not reachable" >&2
            return 1
        fi
        sleep 2
        (( elapsed += 2 ))
        echo -n "."
    done
    echo " reachable"
    open -a Firefox "$open_url"
    echo "Opened Firefox: $open_url"
}

# Returns: "connected <gateway>", "disconnected <msg>", "needs_credentials",
#          "stopped", or "unknown <msg>"
_get_state() {
    osascript << 'APPLESCRIPT'
tell application "System Events"
    if not (exists process "GlobalProtect") then
        return "stopped "
    end if
    tell process "GlobalProtect"
        set gpWin to 0
        repeat with i from 1 to (count of windows)
            tell window i
                if (exists button "Connect") or (exists button "Disconnect") or (exists text field 1) then
                    set gpWin to i
                    exit repeat
                end if
            end tell
        end repeat

        set didOpen to false
        if gpWin is 0 then
            tell menu bar 2
                click menu bar item 1
            end tell
            set didOpen to true
            delay 1.0
            repeat with i from 1 to (count of windows)
                tell window i
                    if (exists button "Connect") or (exists button "Disconnect") or (exists text field 1) then
                        set gpWin to i
                        exit repeat
                    end if
                end tell
            end repeat
        end if

        if gpWin is 0 then
            if didOpen then
                tell menu bar 2
                    click menu bar item 1
                end tell
            end if
            return "unknown (no GP popup found)"
        end if

        try
            tell window gpWin
                set hasDisconnect to exists button "Disconnect"
                set hasConnect to exists button "Connect"
                set fieldCount to count of text fields
                try
                    set txt1 to value of static text 1
                on error
                    set txt1 to ""
                end try
                try
                    set txt2 to value of static text 2
                on error
                    set txt2 to ""
                end try
                if hasDisconnect then
                    set state to "connected " & txt2
                else if fieldCount >= 2 then
                    set state to "needs_credentials "
                else if hasConnect or fieldCount is 1 then
                    set state to "disconnected " & txt1
                else
                    set state to "unknown " & txt1
                end if
            end tell
            if didOpen then
                tell menu bar 2
                    click menu bar item 1
                end tell
            end if
            return state
        on error e
            if didOpen then
                key code 53
            end if
            return "error " & e
        end try
    end tell
end tell
APPLESCRIPT
}

do_connect() {
    local password="$1"
    local username="$2"

    osascript - "$password" "$username" << 'APPLESCRIPT'
on run {thePassword, theUsername}
tell application "System Events"
    if not (exists process "GlobalProtect") then
        error "GlobalProtect is not running"
    end if
    tell process "GlobalProtect"
        -- Search existing windows first (avoid toggling popup closed)
        set gpWin to 0
        repeat with i from 1 to (count of windows)
            tell window i
                if (exists button "Connect") or (exists button "Disconnect") or (exists text field 1) then
                    set gpWin to i
                    exit repeat
                end if
            end tell
        end repeat

        set didOpen to false
        if gpWin is 0 then
            tell menu bar 2
                click menu bar item 1
            end tell
            set didOpen to true
            delay 1.0
            repeat with i from 1 to (count of windows)
                tell window i
                    if (exists button "Connect") or (exists button "Disconnect") or (exists text field 1) then
                        set gpWin to i
                        exit repeat
                    end if
                end tell
            end repeat
        end if

        if gpWin is 0 then
            if didOpen then
                tell menu bar 2
                    click menu bar item 1
                end tell
            end if
            return "not ready (could not find GP popup)"
        end if

        tell window gpWin
            set hasConnect to exists button "Connect"
            set hasDisconnect to exists button "Disconnect"
            set fieldCount to count of text fields
        end tell

        if fieldCount >= 2 then
            -- Credential dialog already open
            tell window gpWin
                set value of text field 1 to theUsername
                set value of text field 2 to thePassword
                click button "Connect"
            end tell
            return "connecting..."

        else if fieldCount is 1 or hasConnect then
            -- Portal screen: click Connect, then poll for credential dialog
            tell window gpWin
                click button "Connect"
            end tell
            set credWin to 0
            repeat 30 times
                delay 0.5
                repeat with i from 1 to (count of windows)
                    tell window i
                        if (count of text fields) >= 2 then
                            set credWin to i
                            exit repeat
                        end if
                    end tell
                end repeat
                if credWin > 0 then exit repeat
            end repeat
            if credWin > 0 then
                tell window credWin
                    set value of text field 1 to theUsername
                    set value of text field 2 to thePassword
                    click button "Connect"
                end tell
                return "connecting..."
            else
                return "connecting... (no credential dialog appeared)"
            end if

        else if hasDisconnect then
            if didOpen then
                tell menu bar 2
                    click menu bar item 1
                end tell
            end if
            return "already connected"

        else
            if didOpen then
                tell menu bar 2
                    click menu bar item 1
                end tell
            end if
            return "not ready"
        end if
    end tell
end tell
end run
APPLESCRIPT
}

do_disconnect() {
    osascript << 'APPLESCRIPT'
tell application "System Events"
    if not (exists process "GlobalProtect") then
        error "GlobalProtect is not running"
    end if
    tell process "GlobalProtect"
        set gpWin to 0
        repeat with i from 1 to (count of windows)
            tell window i
                if (exists button "Connect") or (exists button "Disconnect") or (exists text field 1) then
                    set gpWin to i
                    exit repeat
                end if
            end tell
        end repeat

        set didOpen to false
        if gpWin is 0 then
            tell menu bar 2
                click menu bar item 1
            end tell
            set didOpen to true
            delay 1.0
            repeat with i from 1 to (count of windows)
                tell window i
                    if (exists button "Connect") or (exists button "Disconnect") or (exists text field 1) then
                        set gpWin to i
                        exit repeat
                    end if
                end tell
            end repeat
        end if

        if gpWin is 0 then
            if didOpen then
                tell menu bar 2
                    click menu bar item 1
                end tell
            end if
            return "not ready (could not find GP popup)"
        end if

        tell window gpWin
            set hasDisconnect to exists button "Disconnect"
            set hasConnect to exists button "Connect"
            set fieldCount to count of text fields
        end tell

        if hasDisconnect then
            tell window gpWin
                click button "Disconnect"
            end tell
            return "disconnecting..."
        else if hasConnect or fieldCount >= 1 then
            if didOpen then
                tell menu bar 2
                    click menu bar item 1
                end tell
            end if
            return "already disconnected"
        else
            if didOpen then
                tell menu bar 2
                    click menu bar item 1
                end tell
            end if
            return "not ready"
        end if
    end tell
end tell
APPLESCRIPT
}

CMD="${1:-status}"

case "$CMD" in
    status)
        raw=$(_get_state)
        state="${raw%% *}"
        detail="${raw#* }"
        case "$state" in
            connected)         echo "connected         gateway: $detail" ;;
            disconnected)      echo "disconnected      ($detail)" ;;
            needs_credentials) echo "needs_credentials (run: gp.sh connect)" ;;
            stopped)           echo "stopped           (GlobalProtect not running)" ;;
            unknown*)          echo "unknown           ($detail)" ;;
            error)             echo "error: $detail" >&2; exit 1 ;;
            *)                 echo "$raw" ;;
        esac
        ;;
    connect)
        if ! is_gp_running; then
            echo "GlobalProtect is not running. Start it with: start-globalprotect.sh" >&2
            exit 1
        fi
        password=$(_get_password) || {
            echo "No password in keychain. Run: gp.sh set-password" >&2
            exit 1
        }
        result=$(do_connect "$password" "$USERNAME")
        echo "$result"
        if [[ "$result" == connecting* ]]; then
            _wait_and_open "$POST_CONNECT_CHECK" "$POST_CONNECT_OPEN" "$POST_CONNECT_TIMEOUT"
        fi
        ;;
    disconnect)
        if ! is_gp_running; then
            echo "GlobalProtect is not running" >&2
            exit 1
        fi
        do_disconnect
        ;;
    toggle)
        if ! is_gp_running; then
            echo "GlobalProtect is not running. Start it with: start-globalprotect.sh" >&2
            exit 1
        fi
        raw=$(_get_state)
        state="${raw%% *}"
        if [[ "$state" == "connected" ]]; then
            do_disconnect
        else
            password=$(_get_password) || {
                echo "No password in keychain. Run: gp.sh set-password" >&2
                exit 1
            }
            result=$(do_connect "$password" "$USERNAME")
            echo "$result"
            if [[ "$result" == connecting* ]]; then
                _wait_and_open "$POST_CONNECT_CHECK" "$POST_CONNECT_OPEN" "$POST_CONNECT_TIMEOUT"
            fi
        fi
        ;;
    set-password)
        read -r -s -p "Enter VPN password for $USERNAME@$PORTAL: " pw
        echo
        security delete-generic-password \
            -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" 2>/dev/null || true
        security add-generic-password \
            -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w "$pw"
        echo "Password saved (service: $KEYCHAIN_SERVICE, account: $KEYCHAIN_ACCOUNT)"
        ;;
    *)
        echo "Usage: $(basename "$0") [connect|disconnect|status|toggle|set-password]" >&2
        exit 1
        ;;
esac
