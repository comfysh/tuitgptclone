# Security

## Your data

- TuitMate has **no server**. It talks only to lms.tuit.uz (your LMS data) and, if you set one up,
  the AI provider you chose (Google Gemini or an OpenAI-compatible service).
- Your LMS password (only if you turn on *Remember password*) and AI keys are stored in the device
  keystore: Android Keystore or Windows Credential Manager. They are never written to plain files.
- LMS data is cached on your device for offline use. **Sign out** in Profile deletes it, together
  with the session, saved chats and the home-screen widget data.
- The AI only receives a summary of your LMS data when *Use my LMS data* is on.

## Check that a download is genuine

Download only from this repository's [Releases](../../releases). Every release lists the SHA-256 of
each file in `SHA256SUMS.txt` and in the release notes:

- Windows (PowerShell): `Get-FileHash .\TuitMate-<version>-Setup.exe -Algorithm SHA256`
- Linux / macOS / Termux: `sha256sum -c SHA256SUMS.txt --ignore-missing`

The release notes also show the SHA-256 of the Android signing certificate. Android refuses to
install an update signed with a different key, so an APK from elsewhere cannot replace yours
without uninstalling it first.

## Reporting a problem

If you find a security problem, please report it privately with
[**Report a vulnerability**](../../security/advisories/new) (Security tab) instead of a public issue.
Include what you did, what happened and the app version (Profile › About).
