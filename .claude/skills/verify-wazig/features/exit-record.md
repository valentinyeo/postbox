# Exit record

## Sub-features

- A close request reaching the main window writes one launch-log line: `shutdown: close requested uptime=<seconds>`.
- The end of the window teardown writes `shutdown: clean exit code=0 reason=wm_close uptime=<seconds>`.
- The same teardown writes `%LOCALAPPDATA%\Messages\last-exit.txt`: the exit time in Unix seconds, the version, the reason (`wm_close` or `update`), the uptime and the exit code.
- An updater relaunch writes the same record with `reason=update`.
- The next start logs `startup: previous exit reason=<reason> at=<seconds> version=<version> uptime=<seconds> code=<code>` and deletes the record, so a start that finds nothing logs `startup: previous exit left no record`.

## How to get to it (user POV)

Nothing appears in the window. After Postbox closes, look in `%LOCALAPPDATA%\Messages`: `launch-log.txt` now says who asked the window to close and that the exit was clean, and `last-exit.txt` holds the last clean exit. Start Postbox again and its first lines name the previous exit. A hard kill leaves no record, so the next start says `startup: previous exit left no record` and the missing record is the evidence.

## Driving it with PowerShell UI Automation

Dispatch `feature=exit-record`; changes under `src/exit_record.zig` and its journey also select it on pull requests. The journey runs the offline fixture with two cached chats, asserts `last-exit.txt` does not exist while the window is up, then asks the window to close from outside the process with `CloseMainWindow()`. That is the same `WM_CLOSE` an external script or a person's X produces, and it is not the app's own quit command.

After the process exits, the journey requires one close-request line, one clean-exit line after it and a `last-exit.txt` matching `at=<seconds> version=<version> reason=wm_close uptime=<seconds> code=0`. It then starts the same executable again on the same scratch profile, waits for the main window, requires `startup: previous exit reason=wm_close` to be logged after the clean exit, requires the record to be gone, and requires both cached chats back.

`exit-record.json` keeps the old and new process ids, both log lines, the record text, the startup line, whether the record was consumed and the restored chat count. A full screenshot of the restarted window is saved as `exit-record.png`.

## Gotchas

- Closing the app ends the control pipe, so every control read after the close uses the restarted process id. The journey writes the new id into `session.json` so cleanup closes the right process.
- The record is deleted by the start that reads it. That is what makes a hard kill visible: the next start has nothing to report.
- The launch log rotates at 64 KB. The journey reads the fresh fixture log, which never reaches that size, and it looks for the last matching lines rather than the first.
- `WM_CLOSE` does not say whether a person or a script sent it, and Windows offers no way to tell them apart, so the record names the request, not the caller.
