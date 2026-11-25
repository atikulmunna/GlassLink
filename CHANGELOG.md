# Changelog

## Unreleased

- **Accent colour in dark mode too**, on both apps: icons, switches and highlights use the accent
  (your macOS accent on the Mac; Material You, or Material's palette, on the phone), contacts get
  coloured circles, the battery is green. Backgrounds stay midnight black.
- **New phone icons**, from Material Symbols Rounded: Ring, Send files, Mac's clipboard, Send
  clipboard, Wave, Mirror to Mac and Lock Mac.
- **More quick actions on the phone:** Send clipboard (always shown now), **Mirror to Mac** (opens
  the Phone Screen window on the Mac and starts sharing) and **Lock Mac** (puts the Mac's display
  to sleep, which locks it when a password is required right away).
- **The Mac's System theme follows macOS.** With Theme set to System, GlassLink stayed light even
  when macOS was dark. It now matches macOS, and switches with it.
- **Colourful light mode on the Mac.** Light mode now uses your macOS accent colour for buttons,
  the sidebar, quick actions and signal bars; each contact and app gets its own pastel circle;
  the battery is green (orange, then red, when it runs low); the connected dot is green; and on
  calls, Answer is green and Decline red. Dark mode stays midnight black and white.
- **Material colours in light mode on the phone.** Light mode follows Android's Material design:
  your wallpaper's Material You colours on Android 12 and later, Material's standard palette
  before that. Dark mode stays midnight black and white.

## 0.2.7

**Downloads:** `GlassLink-0.2.7.dmg` for macOS 26 or later (Apple silicon and Intel), and
`GlassLink-0.2.7.apk` for Android 6.0 or later. Check them against `SHA256SUMS`. On 0.2.3 or
later, both apps offer this update themselves. The Android app installs over earlier versions and
keeps your pairing.

- **Ring works on a locked phone.** The phone used to start the sound only once its full-screen
  ringing screen opened, which Android 14 and later don't allow apps to do by default, so a locked
  phone stayed silent. It now rings straight away, at alarm volume, with a "… is ringing this phone"
  notification and a Found it button that stops it.
- **Ping is now Wave**, on both apps; the other device shows "Waved at you 👋".
- **Theme setting on the Mac:** Settings › General › Theme: System, Light or Dark (the phone has
  had this under Settings › Choose theme). The whole window switches straight away, and System
  follows macOS live. In light mode, contact circles are light grey with dark initials.
- **Light mode fix:** prominent buttons such as Show on Phone, Install and Allow showed black text
  on a dark button. They're now solid black with white text in light mode (white with black text
  in dark mode).

## 0.2.6

**Downloads:** `GlassLink-0.2.6.dmg` for macOS 26 or later (Apple silicon and Intel), and
`GlassLink-0.2.6.apk` for Android 6.0 or later. Check them against `SHA256SUMS`. On 0.2.3 or
later, both apps offer this update themselves. The Android app installs over earlier versions and
keeps your pairing.

- **Update checks no longer fail on busy networks.** They used GitHub's API, which allows 60
  requests an hour per internet address, shared by everyone behind it; on many home and mobile
  networks that ran out and the apps said GitHub couldn't be reached. They now read a small
  `latest.json` from the release itself, which has no such limit, and say plainly when GitHub is
  limiting requests.

## 0.2.5

**Downloads:** `GlassLink-0.2.5.dmg` for macOS 26 or later (Apple silicon and Intel), and
`GlassLink-0.2.5.apk` for Android 6.0 or later. Check them against `SHA256SUMS`. On 0.2.3 or
later, both apps offer this update themselves. The Android app installs over earlier versions and
keeps your pairing. GlassLink for Mac has no changes besides the version number.

- **Explains Android's "restricted settings".** Android 13 and later hold back SMS and call-log
  permissions, accessibility and notification access from apps installed from a download. When
  Android refuses one, GlassLink now says how to allow it (App info › ⋮ › Allow restricted
  settings, once) with an Open App info button, instead of failing silently.

## 0.2.4

**Downloads:** `GlassLink-0.2.4.dmg` for macOS 26 or later (Apple silicon and Intel), and
`GlassLink-0.2.4.apk` for Android 6.0 or later. Check them against `SHA256SUMS`. On 0.2.3, both
apps offer this update themselves; on 0.2.2 or older, download it once by hand. The Android app
installs over earlier versions and keeps your pairing.

### Updates

- **The phone reminds you about updates** with a bar at the bottom of the app ("GlassLink … is
  available · Update") until you install it, instead of a one-time dialog.
- **The phone reconnects by itself after updating.** Android doesn't always tell an app it was
  updated, so GlassLink also starts its connection when Android reconnects its notification access
  or accessibility service.
- **The Mac reconnects after updating.** It now waits a moment before reopening, because macOS
  blocks the network for a new app version for its first second; and if announcing ever fails on
  every network, it makes new network connections instead of staying cut off.

## 0.2.3

**Downloads:** `GlassLink-0.2.3.dmg` for macOS 26 or later (Apple silicon and Intel), and
`GlassLink-0.2.3.apk` for Android 6.0 or later. Check them against `SHA256SUMS`. If you have
0.2.2 or older, download both once more by hand: from this version on, the apps update themselves.
The Android app installs over earlier versions and keeps your pairing.

### New

- **Updates inside the apps.** GlassLink for Mac and for Android check GitHub once a day (or when
  you choose Check for Updates) and install the new version for you. On the Mac it downloads,
  verifies, replaces itself and reopens; on the phone you tap Update in Android's installer.
  Mac updates must be signed with GlassLink's release key, and Android only installs updates
  signed like the app. Turn automatic checks off in Settings on either side.
- **Disconnect on the phone**, from its notification or the new power button in the app's top
  bar. GlassLink stays off, and the Mac can't reach the phone, until you tap it again (or
  Reconnect in the notification).
- The Mac app's welcome screen and hints now say GlassLink instead of KDE Connect, with a Get
  GlassLink for Android button.

## 0.2.2

**Downloads:** `GlassLink-0.2.2.dmg` for macOS 26 or later (Apple silicon and Intel), and
`GlassLink-0.2.2.apk` for Android 6.0 or later. Check them against `SHA256SUMS`. Update both
apps. The Android app installs over earlier versions and keeps your pairing.

### Calls

- **Answer and decline WhatsApp calls too**, and calls from other apps that handle their own
  calls. Android ignores outside requests for those, so GlassLink now presses the Answer or
  Decline button in the app's own call notification.
- **Silence works.** It used to do nothing, and the ringer could come back at full volume after
  the call. It now mutes the ringer, or switches to vibrate where Android requires Do Not Disturb
  access, and restores your previous setting afterwards.
- Silence, Decline and Answer are now equal round buttons on the call banner and in the menu bar.
  Answer stands out by its solid fill.

## 0.2.1

**Downloads:** `GlassLink-0.2.1.dmg` for macOS 26 or later (Apple silicon and Intel), and
`GlassLink-0.2.1.apk` for Android 6.0 or later. Check them against `SHA256SUMS`. Update both
apps: answering calls needs the new version on the Mac and on the phone. The Android app installs
over earlier versions and keeps your pairing.

### Fixes

- **Calls and notifications no longer go missing.** macOS reports network changes every few
  seconds even when nothing changed, and GlassLink announced itself again each time, which made
  the phone drop and rebuild its connection. Anything sent during the swap was lost. GlassLink now
  only announces when the Mac's network really changes.
- Only one copy of GlassLink for Mac runs at a time; a second copy quits.
- Incoming-call alerts are ordinary banners now, so they show even without a special entitlement.

### New

- **Answer, decline and end calls from your Mac**, from the call banner, the menu bar or the
  notification. The call stays on the phone: talk on the phone or its earbuds.
- **Setup checks on the Overview:** GlassLink says when macOS has its notifications turned off, or
  when the phone is still waiting for a permission, with buttons to fix either.

## 0.2.0

**Downloads:** `GlassLink-0.2.0.dmg` for macOS 26 or later (Apple silicon and Intel), and
`GlassLink-0.2.0.apk` for Android 6.0 or later. Check them against `SHA256SUMS`. Update both
apps: mirroring needs the new version on the Mac and on the phone. The Android app installs over
earlier versions and keeps your pairing.

### Screen mirroring

- **See and use your phone from your Mac.** Click **Mirror** on the Overview (or press **⇧⌘M**),
  tap **Start** on the phone, and its screen, or just one app on Android 14 or later, appears in a
  phone-shaped window.
- Click to tap, hold for a long press, drag to swipe, scroll with the trackpad, and right-click or
  press **Esc** for Back. Back, Home and Recents buttons sit under the screen.
- **Type on your Mac's keyboard** into the phone's text fields (Android 14 or later). Return does
  what the phone's Enter key would, **⌘↩** sends, **⌘A/⌘C/⌘X/⌘Z** work, and **⌘V** pastes the
  Mac's clipboard.
- Controlling the phone uses GlassLink's accessibility service. If it's off, the Mac and the phone
  both explain how to turn it on.

### GlassLink for Android

- The Mac now sees the phone's own name, as set in the phone's settings, instead of its model name.

## 0.1.2

**Downloads:** `GlassLink-0.1.2.dmg` for macOS 26 or later (Apple silicon and Intel), and
`GlassLink-0.1.2.apk` for Android 6.0 or later. Check them against `SHA256SUMS`. The Android app
installs over earlier versions and keeps your pairing.

### GlassLink for Android

- When the Mac's name changes, the title at the top of its screen now updates right away, instead
  of keeping the old name until you reopen the screen.

### GlassLink for Mac

- No changes besides the version number.

## 0.1.1

A small update to 0.1.0.

**Downloads:** `GlassLink-0.1.1.dmg` for macOS 26 or later (Apple silicon and Intel), and
`GlassLink-0.1.1.apk` for Android 6.0 or later. Check them against `SHA256SUMS`. The Android app
installs over 0.1.0 and keeps your pairing.

### GlassLink for Mac

- The sidebar icons are white in dark mode and black in light mode. macOS 27 was colouring them with
  the system accent colour, which didn't fit the midnight-and-white design.

### GlassLink for Android

- No changes besides the version number.

## 0.1.0

The first release of GlassLink: a native Mac app and an Android companion that bring your phone to
your Mac over your own Wi-Fi.

**Downloads:** `GlassLink-0.1.0.dmg` for macOS 26 or later (Apple silicon and Intel), and
`GlassLink-0.1.0.apk` for Android 6.0 or later. Check them against `SHA256SUMS`.

**The Mac app is not notarized yet.** The first time you open it, go to System Settings › Privacy &
Security and click Open Anyway (the note in the DMG walks through it).

### GlassLink for Mac

- Pairing with a matching code on both screens; the phone's certificate is pinned.
- Notifications with app icons, inline reply, actions and dismiss, mirrored to Notification Center.
- SMS conversations with contact names, and replies from the Mac.
- An incoming-call banner with Silence, and missed-call alerts.
- Clipboard sync for text, and for images with GlassLink for Android; Get Phone's Clipboard.
- Phone screenshots go straight to the clipboard, with a floating thumbnail you can drag; Mac
  screenshots go to the phone's clipboard.
- Drag-and-drop file transfer, and sending links and text.
- Ring your phone; the phone can ring the Mac.
- Battery, signal and the phone's home-screen wallpaper on the Overview, plus a menu bar panel.
- Midnight black-and-white design that follows the system's dark or light mode.

### GlassLink for Android

- Based on KDE Connect for Android 1.37.3; compatible with KDE Connect devices.
- New: instant screenshot push, image copy and paste both ways, Get Mac's Clipboard, wallpaper
  sharing, and Ring and Ping tiles.
- Midnight black-and-white theme, a device screen with your Mac drawn on it, and the GlassLink icon.
