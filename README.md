# ePlanner relay script test

Scratch repo to test the RTMS ePlanner relay PowerShell scripts on a **real Windows**
environment (GitHub Actions `windows-latest` = Windows Server 2022, Windows PowerShell 5.1),
since local testing on macOS/Linux cannot cover Windows-specific behaviour.

## What the workflow checks

**Job 1 — syntax and batch logic**
- Both scripts parse cleanly under Windows PowerShell 5.1
- Batch selection: a complete batch (`.z01`, `.z02`, `.zip`) is picked up, an incomplete
  batch (no `.zip` yet) is skipped, unrelated files are ignored, and split parts are
  ordered before the `.zip`

**Job 2 — real WinSCP transfer**
- Installs WinSCP and starts Windows' built-in OpenSSH server on the runner, so the
  script transfers to a genuine SFTP endpoint on `127.0.0.1`
- Patches the shipped script with test values and runs it unmodified otherwise
- Verifies the complete batch arrived at the destination and was removed from the source,
  and that the incomplete batch was left in place

The point of job 2 is to prove the `& $winscp @arguments` call survives Windows
PowerShell 5.1 argument passing — arguments contain both spaces and embedded quotes
(`-hostkey="ssh-ed25519 256 SHA256:..."`), which 5.1 is known to handle poorly.
If it fails here, the scripts should switch to WinSCP's `/script=<file>` form.

## Running it

Actions tab -> "Test ePlanner relay scripts on Windows" -> Run workflow.
Also runs automatically on push.
