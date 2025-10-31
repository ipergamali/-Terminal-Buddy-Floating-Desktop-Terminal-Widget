#!/usr/bin/env python3
"""
Terminal Buddy shell runner.

Executes commands on behalf of the QML front-end, persists history,
and returns structured JSON describing the outcome.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


HISTORY_DIR = Path.home() / ".local" / "share" / "terminalbuddy"
HISTORY_FILE = HISTORY_DIR / "history.json"
DEFAULT_HISTORY: Dict[str, Any] = {"last_command": "", "history": []}
MAX_HISTORY_DEFAULT = 100


def load_history() -> Dict[str, Any]:
    """
    Load command history from disk, falling back to defaults when missing
    or malformed.
    """
    if not HISTORY_FILE.exists():
        return DEFAULT_HISTORY.copy()

    try:
        with HISTORY_FILE.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (json.JSONDecodeError, OSError):
        return DEFAULT_HISTORY.copy()

    if not isinstance(data, dict):
        return DEFAULT_HISTORY.copy()

    history = data.get("history", [])
    last_command = data.get("last_command", "")

    if not isinstance(history, list):
        history = []

    serialised = DEFAULT_HISTORY.copy()
    serialised["history"] = [str(entry) for entry in history]
    serialised["last_command"] = str(last_command) if last_command else ""
    return serialised


def save_history(history: Dict[str, Any]) -> None:
    """
    Persist the history payload to disk.
    """
    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    try:
        with HISTORY_FILE.open("w", encoding="utf-8") as handle:
            json.dump(history, handle, indent=2, ensure_ascii=False)
    except OSError:
        # History persistence failures should never break command execution.
        pass


def detect_shell() -> str:
    """
    Determine the most appropriate shell to execute commands under.
    """
    env_shell = os.environ.get("TERMINAL_BUDDY_SHELL") or os.environ.get("SHELL")
    if env_shell and Path(env_shell).exists():
        return env_shell

    candidates = (
        "/usr/bin/zsh",
        "/usr/bin/fish",
        "/usr/bin/bash",
        "/bin/bash",
        "/bin/zsh",
        "/bin/fish",
        "/bin/sh",
    )

    for candidate in candidates:
        if Path(candidate).exists():
            return candidate

    return "/bin/sh"


def decode_command(encoded: Optional[str], command: Optional[str]) -> str:
    """
    Decode the incoming command either from base64 (`encoded`) or the
    plain `command` string. Returns an empty string on failure.
    """
    if encoded:
        try:
            return base64.b64decode(encoded).decode("utf-8", errors="ignore")
        except (ValueError, UnicodeDecodeError):
            return ""
    return command or ""


def update_history(history: Dict[str, Any], command: str, limit: int) -> None:
    """
    Store the command in the history list while maintaining the configured limit.
    """
    commands = [entry for entry in history.get("history", []) if entry != command]
    commands.insert(0, command)
    history["history"] = commands[:limit]
    history["last_command"] = command


def run_command(command: str, history: Dict[str, Any], max_history: int) -> Dict[str, Any]:
    """
    Execute the supplied command using the detected shell and return a response payload.
    """
    shell_path = detect_shell()
    response: Dict[str, Any] = {
        "type": "run",
        "command": command,
        "stdout": "",
        "stderr": "",
        "exit_code": 0,
        "shell": shell_path,
        "history": history.get("history", []),
        "last_command": history.get("last_command", ""),
    }

    lowered = command.strip().lower()
    if lowered in {"", "clear", "cls"}:
        if lowered:
            response["action"] = "clear"
        return response

    if lowered in {"exit", "quit"}:
        response["action"] = "exit"
        return response

    try:
        completed = subprocess.run(
            command,
            shell=True,
            executable=shell_path,
            capture_output=True,
            text=True,
            check=False,
        )
        response["stdout"] = completed.stdout
        response["stderr"] = completed.stderr
        response["exit_code"] = completed.returncode
    except Exception as execution_error:  # noqa: BLE001 - surface unexpected issues
        response["stderr"] = f"Execution error: {execution_error}"
        response["exit_code"] = -1

    update_history(history, command, max_history)
    save_history(history)
    response["history"] = history["history"]
    response["last_command"] = history["last_command"]
    return response


def emit(payload: Dict[str, Any]) -> None:
    """
    Print the response payload as JSON for consumption by QML.
    """
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    sys.stdout.flush()


def parse_args(argv: List[str]) -> argparse.Namespace:
    """
    Parse CLI arguments.
    """
    parser = argparse.ArgumentParser(description="Terminal Buddy command runner")
    parser.add_argument("--run", action="store_true", help="Execute a command")
    parser.add_argument("--encoded", help="Base64 encoded command payload")
    parser.add_argument("--command", help="Raw command string")
    parser.add_argument("--history", action="store_true", help="Return stored history")
    parser.add_argument(
        "--max-history",
        type=int,
        default=MAX_HISTORY_DEFAULT,
        help="Maximum number of history entries to store",
    )
    return parser.parse_args(argv)


def main(argv: List[str]) -> int:
    args = parse_args(argv)
    history = load_history()

    if args.history:
        payload = {
            "type": "history",
            "history": history.get("history", []),
            "last_command": history.get("last_command", ""),
            "shell": detect_shell(),
        }
        emit(payload)
        return 0

    if not args.run:
        emit(
            {
                "type": "error",
                "stderr": "No action supplied. Use --run or --history.",
                "exit_code": 1,
            }
        )
        return 1

    command = decode_command(args.encoded, args.command).strip()
    response = run_command(command, history, max(1, args.max_history))
    emit(response)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
