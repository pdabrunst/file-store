#!/usr/bin/env bash
set -euo pipefail

DEP_FLAG="$HOME/.hermes/.deps_installed"

# One-time dependency installer with OS-aware package manager detection.
ensure_dependencies() {
    [[ -f "$DEP_FLAG" ]] && return 0

    echo "Checking dependencies..."

    missing=()
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v whiptail >/dev/null 2>&1 || missing+=("whiptail")

    if [[ "${#missing[@]}" -eq 0 ]]; then
        touch "$DEP_FLAG"
        return 0
    fi

    echo "Missing: ${missing[*]}"
    echo "Detecting package manager..."

    pkg_manager=""
    if command -v apt-get >/dev/null 2>&1; then
        pkg_manager="apt"
    elif command -v dnf >/dev/null 2>&1; then
        pkg_manager="dnf"
    elif command -v yum >/dev/null 2>&1; then
        pkg_manager="yum"
    elif command -v pacman >/dev/null 2>&1; then
        pkg_manager="pacman"
    elif command -v brew >/dev/null 2>&1; then
        pkg_manager="brew"
    elif command -v apk >/dev/null 2>&1; then
        pkg_manager="apk"
    elif command -v zypper >/dev/null 2>&1; then
        pkg_manager="zypper"
    elif command -v pkg >/dev/null 2>&1; then
        pkg_manager="pkg"
    fi

    if [[ -z "$pkg_manager" ]]; then
        echo "ERROR: Could not detect package manager. Please install manually: ${missing[*]}"
        exit 1
    fi

    echo "Using package manager: $pkg_manager"

    case "$pkg_manager" in
        apt)
            sudo apt-get update -qq
            sudo apt-get install -y -qq "${missing[@]}"
            ;;
        dnf)
            sudo dnf install -y -q "${missing[@]}"
            ;;
        yum)
            sudo yum install -y -q "${missing[@]}"
            ;;
        pacman)
            sudo pacman -Sy --noconfirm --quiet "${missing[@]}"
            ;;
        brew)
            brew install "${missing[@]}"
            ;;
        apk)
            sudo apk add --no-progress "${missing[@]}"
            ;;
        zypper)
            sudo zypper install -y "${missing[@]}"
            ;;
        pkg)
            sudo pkg install -y "${missing[@]}"
            ;;
    esac

    touch "$DEP_FLAG"
    echo "Dependencies installed."
}

ensure_dependencies

# Locate Hermes's state.db by checking known install locations.
find_hermes_db() {
    local candidates=()

    # Respect Hermes's own home hint if present
    if [[ -n "${HERMES_REAL_HOME:-}" ]]; then
        candidates+=("$HERMES_REAL_HOME/.hermes/state.db")
    fi

    # Standard home-based install
    candidates+=("$HOME/.hermes/state.db")

    # Common absolute locations
    candidates+=(
        "/root/.hermes/state.db"
        "/usr/local/share/hermes/state.db"
        "/opt/hermes/state.db"
    )

    # If a hermes binary exists nearby, infer from its prefix
    local hermes_bin
    hermes_bin="$(command -v hermes || true)"
    if [[ -n "$hermes_bin" ]]; then
        local prefix
        prefix="$(dirname "$(dirname "$hermes_bin")")"
        candidates+=("$prefix/share/hermes/state.db")
        candidates+=("$prefix/.hermes/state.db")
    fi

    # Return the first existing candidate
    for db in "${candidates[@]}"; do
        if [[ -f "$db" ]]; then
            echo "$db"
            return 0
        fi
    done

    # Last resort: bounded filesystem search from /
    timeout 10s find / -name "state.db" -path "*/.hermes/*" -type f 2>/dev/null && return 0

    echo ""
    return 1
}

DB="$(find_hermes_db || true)"
if [[ -z "$DB" || ! -f "$DB" ]]; then
    echo "ERROR: Could not locate Hermes database (state.db)."
    exit 1
fi

# Query Hermes SQLite state for existing chats in the default profile.
get_sessions() {
    python3 -c "
import sqlite3
conn = sqlite3.connect('$DB')
cur = conn.cursor()
cur.execute('''
    SELECT id, title, datetime(started_at, 'unixepoch') as started
    FROM sessions
    WHERE profile_name = 'default'
      AND archived = 0
    ORDER BY started_at ASC
''')
for sid, title, started in cur.fetchall():
    title = (title or '(untitled)').replace('|', '/')
    print(f'{title}|{sid}|{started}')
"
}

delete_chat_menu() {
    clear
    mapfile -t lines < <(get_sessions)

    chat_titles=()
    chat_ids=()
    for line in "${lines[@]}"; do
        IFS='|' read -r title sid started <<< "$line"
        chat_titles+=("$title [$started]")
        chat_ids+=("$sid")
    done

    chat_titles+=("Back")
    chat_ids+=("__BACK__")

    PS3="Enter numbers to delete (space-separated), or choose one: "

    while true; do
        echo "Chats:"
        for i in "${!chat_titles[@]}"; do
            printf "  %d) %s\n" "$((i+1))" "${chat_titles[$i]}"
        done
        read -rp "Select chats to delete (e.g. 1 2 3, 3-7, or 'b' to go back): " selections

        if [[ "$selections" == "b" ]]; then
            main_menu
            return
        fi

        # Expand ranges like 3-7 into individual numbers
        expanded=()
        for token in $selections; do
            if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                start="${BASH_REMATCH[1]}"
                end="${BASH_REMATCH[2]}"
                if (( start <= end )); then
                    for ((n=start; n<=end; n++)); do
                        expanded+=("$n")
                    done
                else
                    for ((n=start; n>=end; n--)); do
                        expanded+=("$n")
                    done
                fi
            elif [[ "$token" =~ ^[0-9]+$ ]]; then
                expanded+=("$token")
            fi
        done

        to_delete=()
        for idx in "${expanded[@]}"; do
            if (( idx >= 1 && idx <= ${#chat_ids[@]} )); then
                sid="${chat_ids[$((idx-1))]}"
                if [[ "$sid" != "__BACK__" ]]; then
                    to_delete+=("$sid")
                fi
            fi
        done

        # Deduplicate
        if [[ "${#to_delete[@]}" -gt 1 ]]; then
            declare -A seen
            deduped=()
            for sid in "${to_delete[@]}"; do
                if [[ -z "${seen[$sid]:-}" ]]; then
                    deduped+=("$sid")
                    seen[$sid]=1
                fi
            done
            to_delete=("${deduped[@]}")
        fi

        if [[ "${#to_delete[@]}" -eq 0 ]]; then
            echo "No valid chats selected."
            continue
        fi

        echo "Selected ${#to_delete[@]} chat(s) for deletion."
        if ! whiptail --yesno "Delete ${#to_delete[@]} chat(s)? This cannot be undone." 10 60; then
            continue
        fi

        for sid in "${to_delete[@]}"; do
            hermes sessions delete "$sid" --yes >/dev/null 2>&1 || true
        done

        whiptail --msgbox "Deleted ${#to_delete[@]} chat(s)." 10 60
        main_menu
        return
    done
}

main_menu() {
    clear
    mapfile -t lines < <(get_sessions)

    titles=()
    ids=()
    for line in "${lines[@]}"; do
        IFS='|' read -r title sid started <<< "$line"
        titles+=("$title [$started]")
        ids+=("$sid")
    done

    titles+=("New Chat")
    ids+=("__NEW__")

    titles+=("Delete Chat")
    ids+=("__DEL__")

    titles+=("Exit")
    ids+=("__EXIT__")

    while true; do
        echo "Main Menu:"
        for i in "${!titles[@]}"; do
            printf "  %d) %s\n" "$((i+1))" "${titles[$i]}"
        done
        read -rp "Enter number (or 'b' to go back): " reply

        if [[ "$reply" == "b" ]]; then
            continue
        fi

        if [[ ! "$reply" =~ ^[0-9]+$ ]]; then
            echo "Please enter a valid number."
            continue
        fi

        idx=$((reply - 1))
        if (( idx < 0 || idx >= ${#ids[@]} )); then
            echo "Number out of range."
            continue
        fi

        sid="${ids[$idx]}"

        if [[ "$sid" == "__NEW__" ]]; then
            read -rp "Enter a name for the new chat: " chat_name
            chat_name="${chat_name:-New Chat}"
            exec hermes chat --continue "$chat_name" --create-if-missing
        elif [[ "$sid" == "__DEL__" ]]; then
            delete_chat_menu
        elif [[ "$sid" == "__EXIT__" ]]; then
            exit 0
        else
            exec hermes chat --resume "$sid"
        fi
    done
}

main_menu
