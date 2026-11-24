# ArinaDesk branch notes

This branch (`arinadesk`) adds UI buttons to the RustDesk client built by `generator-windows.yml`.

- Patch script: `.github/arinadesk/arinadesk_patch.py` (targets RustDesk 1.5.3)
- It is applied by the workflow right after the "apply theme colors" step.
- If a RustDesk upgrade changes the UI code, the script fails on purpose and the build stops.
