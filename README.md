# Obsidian Nudge

Obsidian Nudge is an Android app that reminds you to revisit notes from your
Obsidian vault. It reads Markdown from GitHub, picks a note that is due for
review, and sends a notification. Review ratings stay on your phone.

## Install and connect a vault

1. Download the APK from the [latest release](https://github.com/knmn2000/obsidian-nudge-android/releases/latest)
   and open it on your Android phone to install it. Allow notifications when
   prompted.
2. Keep a copy of your vault in a GitHub repository with the Markdown files
   relative to the repository root. A private repository works with a
   [fine-grained GitHub token](https://github.com/settings/personal-access-tokens/new)
   scoped to that repository with **Contents: Read-only**. Public repositories
   can leave the token blank.
3. In the app, enter the repository as `owner/name` and the branch that holds your
   notes. Tap **Save** to sync. The app stores your token in Android secure
   storage.
4. Optionally enter a folder path such as `Study/Review` to get reminders only
   from that folder and its subfolders. Leave it blank to use the whole vault.
   To open notes in Obsidian, enter the exact name of the vault already open in
   Obsidian on your phone. Its file paths should match the GitHub copy.

You can edit these fields under **Settings → Vault setup**. The app syncs daily
and sends a reminder about every five hours outside quiet hours. You can adjust
the schedule in Settings or use **Nudge now** to try it. If Android delays
background reminders, check whether battery settings restrict the app.

Tap a reminder to read and rate the note. **Didn't get it**, **Forgot**, **Meh**
and **Know it** schedule it for the next review, about a day, three days or 21
days later, respectively.

## Add quiz questions

Put a section like this at the end of a Markdown note. The app can use a
question from it in the notification and lets you reveal the answer in the app.

```markdown
## Quiz
Q: Why does a log-based message broker allow replay?
A: Consumers track an offset and can go back to an earlier position in the log.
```

## Build from source

With Flutter and the Android SDK installed:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The APK is at `build/app/outputs/flutter-apk/app-release.apk`.
