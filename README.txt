JASPER BROWSER LITE v0.6.6 — CONTINUOUS DESKTOP CHAOS & USB PORTABLE MODE
==========================================================================

Desktop icons and previously captured ordinary app windows randomize repeatedly during one horror event until the Jasper Browser profile closes. The effect runs once until Recovery restores the saved layout and resets its one-shot marker. Escape or Recovery can stop it early. Pinned taskbar icon order remains unchanged; running-app buttons flash as the supported fallback.

WHAT THIS BUILD DOES
--------------------
This installer intentionally uses the existing Firefox runtime in its original Program Files folder. It does NOT copy a second browser runtime into AppData and does NOT overwrite firefox.exe. Instead it adds Jasper Search and extension policies to that installation, creates a dedicated Jasper profile, styles that profile, and launches it through a Jasper Browser shortcut.

IMPORTANT: this is an in-place repackaging/customization of the installed Firefox/Gecko application, not a source-built independent browser. The Firefox executable and some built-in internal labels remain Firefox. The visible Jasper title/icon are applied at runtime.

NEW TAB FIX
-----------
The prior release told New Tab Override to open file:///.../StartPage.html. Firefox extensions block this kind of direct local-file access, which caused the error in the screenshot.

v0.5.0 serves the Jasper homepage from:
  http://127.0.0.1:18765/StartPage.html

A small bundled PowerShell static server binds ONLY to IPv4 loopback (127.0.0.1), serves the packaged StartPage.html and assets, rejects paths outside the site folder, and supports a /health check. A hidden Startup shortcut launches the host at Windows logon, and the Jasper launcher starts or refreshes its matching v0.6.4 helper if needed. This allows New Tab Override to open an ordinary HTTP URL without weakening file security.

V0.6.4 FIX: corrected the desktop icon native API import. OpenProcess is imported from kernel32.dll; v0.6.3 incorrectly imported it from user32.dll, which caused desktop icon capture to fail with EntryPointNotFoundException and report 0 icon slots.

Taskbar limitation: this build does not physically reorder pinned taskbar icons. Windows offers no supported, stable per-session API for that operation; only running-app buttons may flash as a visual cue.


USB FLASH / PORTABLE USER MODE (v0.6.6)
-------------------------------------
- Run Flash-JasperBrowser-USB.bat from the extracted package to choose a verified USB/removable drive. The tool shows the drive model, label, and size, then requires you to type FORMAT X: before formatting it as exFAT. Formatting requires a normal Windows UAC/admin approval because it erases a disk.
- The flashed drive includes Start-JasperBrowser-USB.bat. On another PC, the user must launch it manually. Windows does not auto-run executable installers merely because a USB drive is plugged in; this package does not bypass UAC or hide installation.
- The USB launcher installs only a per-user runtime under %LOCALAPPDATA%\JasperBrowserLiteUSB, uses an isolated Firefox profile, and serves its homepage from 127.0.0.1:18766 so it can coexist with a standard Jasper Browser install. It does not write Firefox installation-wide policies.
- If Firefox is absent, the user-launched USB setup starts winget to install Mozilla Firefox and then continues when Firefox is detected. Windows may still show normal security/UAC prompts. Windows blocks silent execution just from USB insertion; this package does not bypass that protection.
- Recovery is available from the desktop/Start menu after the first run, including if the USB is unplugged. Removing the USB does not automatically remove the per-user runtime/profile; run the USB recovery menu or manually uninstall the USB profile/runtime as described in USB-START-HERE.txt.
- Portable mode opens Jasper Search as its initial page. Because it does not write global Firefox enterprise policies or force-install extensions, tab override/ad-blocking behavior can differ from the standard admin-approved install.

PROGRAM FILES INSTALL
---------------------
1. Close all Firefox windows.
2. Extract this ZIP.
3. Double-click Install-JasperBrowser.bat.
4. Approve the Windows UAC prompt because writing to Program Files requires administrator access.
5. Start Jasper Browser from its new Start-menu/desktop shortcut.

The installer detects firefox.exe and reads its PE architecture. If Firefox is missing, it installs Mozilla.Firefox through winget for the operating-system architecture (x86, x64, or ARM64) and then configures that runtime. An already-installed x86 Firefox is reused as x86; the installer does not replace an existing runtime architecture. It writes distribution\policies.json into that installation folder. It backs up any previous policies.json into:
  %LOCALAPPDATA%\JasperBrowserLite\Backup\policies.json.original
If there was no prior policy, a marker file is stored so uninstall can remove Jasper's policy.

GLOBAL POLICY WARNING
---------------------
Because this is an in-place install, Firefox Enterprise policies are installation-wide:
- Jasper Search is set as the default search provider.
- New Tab Override is force-installed and points to the localhost Jasper page.
- uBlock Origin is force-installed as the ad blocker.
These managed settings can therefore affect other profiles that use this same Firefox installation. The Jasper bookmarks, cookies, history, extensions, and userChrome styling use their own dedicated profile at:
  %LOCALAPPDATA%\JasperBrowserLite\Profile

LOCAL PAGE HOST
---------------
The host listens on 127.0.0.1:18765 only; it is not exposed to the LAN. A small hidden shortcut under the user's Startup folder launches it on login. If that port is already occupied by another program, the Jasper launcher will report that it couldn't verify the Jasper local page host.

FEATURES
--------
- Browser launch uses a Windows Script Host shim to run PowerShell hidden. No PowerShell/CMD terminal should remain alongside Jasper Browser.
- The deep-scroll horror trigger is a 36px completely textless button with subtle red pulsing and clear hover/focus feedback, located after a long blank scroll runway. Horror progression is button-driven; reloads do not advance stages.
- After the successful install prompt, pressing Enter briefly clears the installer console and shows the requested string in red for less than a second. This is a visual-only effect.
- Jasper fox-and-globe icon on Jasper shortcuts, website favicon, search provider, and browser window icon.
- Jasper Browser visible title and high-contrast light tab text in the Jasper profile.
- Google-powered Jasper Search as the managed default and live suggestions on the homepage.
- South Park Studios shortcut.
- Settings and Chrome Web Store links.
- uBlock Origin forced-installed globally; uBlock filtering is disabled only on South Park domains because the official player may break with ad blocking.
- Jasper profile uses Standard tracking protection to avoid Strict-mode site breakage documented for South Park.
- Chrome extension import helper for inspecting/extracting .crx/.zip packages and attempting temporary testing of compatible WebExtensions.


ADULT-SITE BLOCKING
------------------
- Jasper Search intercepts direct URLs to domains listed in adult-site-blocklist.txt and displays a “STOP WHAT ARE YOU DOING” warning. A hidden local helper shakes visible normal application windows and the cursor for up to 5.2 seconds. Press Escape, click RETURN TO JASPER, or run Recovery to stop the event. Intentional mouse movement disables cursor jitter; window positions are restored at the end.
- Firefox Enterprise WebsiteFilter hard-blocks the same list. This policy is installation-wide and affects every Firefox profile that uses the same Firefox executable, not only Jasper's dedicated profile. The installer makes a backup of any pre-existing policies.json; the uninstall script restores that backup.
- The list is curated and not exhaustive. Edit adult-site-blocklist.txt before installing to customize it. The host-page scare only triggers when a matching destination is typed or linked from Jasper Search; a browser policy block in another page may show Firefox's own policy-block page without the scare animation.
- Typing verity.com in Jasper Search opens the provided YouTube video: https://youtu.be/tVlKLpxyCBY?si=yzL3pFi6hJ8ArIp6. The video is a link, not embedded or downloaded.

CHROME WEB STORE LIMITATION
---------------------------
The Chrome Web Store link lets you browse the store; it does NOT make Chrome extensions directly installable in Firefox. The importer extracts and inspects compatible packages. Some Chrome-only APIs won't work, and temporary imports do not persist after restart. It does not bypass Mozilla signing requirements.

UNINSTALL / ROLLBACK
--------------------
Run Uninstall-JasperBrowser.bat and approve elevation. The script removes Jasper shortcuts and the Startup host shortcut, then restores the original policies.json or removes Jasper's policy if there was no original file. You can optionally delete Jasper profile/homepage assets after restoring the policy.

DESKTOP EFFECTS / LIMITATIONS
-----------------------------
- v0.6.3 uses the desktop ListView's 32-bit item-position message and temporarily clears its auto-arrange style while shuffling saved desktop icon slots. It logs discovered, requested, and observed icon moves to %LOCALAPPDATA%\JasperBrowserLite\desktop-layout.log. Recovery restores icon positions and the original desktop ListView style.
- Ordinary visible application windows are moved to randomized positions, and Recovery attempts to return each still-open window to its saved position. Closed/reopened windows may have new handles.
- Taskbar app buttons flash in randomized order. The pinned taskbar icon order itself is NOT reordered: Windows exposes supported taskbar pinning/layout mechanisms, but not a stable session API for arbitrary temporary reordering, and applying taskbar layout policy can require a sign-out or policy refresh. See Microsoft's taskbar documentation. [https://learn.microsoft.com/en-us/windows/configuration/taskbar/pinned-apps]
- The final scream and buffer sound are synthesized audio; the buffer loop stops when Jasper closes or Recovery is run. This is only a simulated crash sound, not a real BSOD.

SAFETY / TEST STATUS
--------------------
- Browser executable files in Program Files are not overwritten or binary-patched.
- Original Firefox profile files are not deleted.
- The prior policies.json is backed up before replacement.
- The localhost server only serves files from the Jasper Site folder and only binds to 127.0.0.1.
- Static package checks were run, but this has NOT been end-to-end tested on your Windows computer. After installation, verify about:policies, open about:addons to confirm uBlock Origin and New Tab Override are installed, then press Ctrl+T to check the Jasper page.

V0.5.2 NOTES
------------
- Added uBlock Origin trusted-site directives for southparkstudios.com and southpark.cc.com only; ad blocking remains enabled elsewhere.
- Set Jasper profile tracking-protection category to Standard. South Park video availability can still depend on regional rights and site-side restrictions.
- Added a distinct Windows AppUserModelID to Jasper shortcuts and its browser window, alongside the custom icon. Windows may require unpinning the old Firefox taskbar pin and launching/pinning Jasper Browser from its own shortcut.
- The in-place firefox.exe is not binary-patched or re-signed; Firefox/Gecko remains the engine underneath.


Version 0.5.5 fix
- The start page now includes a long blank scrolling area before the small textless horror trigger, so the button is actually deep down the page rather than directly under the ordinary content. It remains faint, with a slightly clearer hover target.
- Windows-facing Jasper title/icon/shortcut branding is used for Jasper Browser. The underlying Mozilla-signed runtime file remains firefox.exe; renaming that binary would interfere with runtime/updater assumptions, so this build does not rename or patch it.


V0.5.6 FIXES
------------
- Increased the deep hidden trigger from a nearly invisible 15px dot to a 36px textless button with a low-key red pulse. It is still placed after the long blank scroll runway.
- Added a brief real console window on every Jasper Browser launcher start; it closes itself after two seconds.
- Static checks were run in this environment; the PowerShell launcher and visible console behavior still need confirmation on Windows.


V0.5.7 HELPER REPAIR
--------------------
- The local host /health endpoint is versioned (JASPER_OK|0.6.3), so the launcher can detect and restart an old Jasper helper that is still running in memory.
- Host startup repairs a missing or empty horror-token file, preventing the /api/state 403 that caused the “Jasper Browser horror helper could not respond” alert.
- Browser shortcuts now target a hidden WScript launcher; the visible two-second startup terminal was removed.
- If Jasper is already installed, close Jasper Browser and run Repair-JasperBrowser-Fix.bat from the extracted package. It updates Jasper's page/helper and Jasper shortcuts only; it does not reinstall Firefox, change Firefox binaries, or touch the ordinary Firefox profile.


v0.5.8 SCATTERED ??? WINDOWS
---------------------------
- The ??? finale now opens 36 Windows dialog-style windows across the primary screen in a quick burst instead of presenting one centered modal message box at a time.
- Each window has OK and normal close controls. Escape or the standalone Jasper Browser Recovery tool closes the entire group. No new windows are spawned after the initial 36.
- The dialog sequence is bounded and remains cancellable. This package was not executed on Windows in the build environment; confirm behavior on the target computer.


v0.5.9 RELOAD + CURSED-TEXT FIX
-------------------------------
- The finale count begins after the user activates the third-stage horror search. Reload the local Jasper Search homepage 10 times; the count persists in Jasper's local state. The tenth reload starts the finale and requests the reversible wallpaper/audio worker exactly once.
- Reloading a third-party Google results page does not run Jasper's local counter; return to/reload the Jasper Search page itself.
- At Stage 3, visible homepage copy is replaced with emoji/cursed glyphs. The control remains labeled ???.
- If the prior build already counted 10 reloads but failed to change the wallpaper, v0.5.9 retries the wallpaper/audio action on the next Jasper Search reload until Windows reports the wallpaper was applied. The helper logs success to `%LOCALAPPDATA%\JasperBrowserLite\horror-worker.log` and failures to `horror-worker-errors.log`.
- The black wallpaper asset is a 1920×1080 solid-black BMP. Use Jasper Browser Recovery to restore the saved wallpaper.
- This archive was statically checked, not executed on Windows.


V0.5.10 BUTTON-ADVANCED HORROR
------------------------------
- The horror no longer depends on reloading Jasper Search 10 times. Reloads do not advance the finale.
- After the cursed-text stage, click the deep ??? trigger (or submit a search) to open the symbol-only offline scene; the local helper requests the reversible wallpaper/audio effect on that action.
- Click the ??? button on the offline scene to begin the farewell/fire finale. This is a deliberate button press instead of ten reloads.
- The hidden secret button stays labeled ??? after the corruption stage. The 36-window burst remains bounded and can be dismissed with Escape or Jasper Browser Recovery.
- The standalone Recovery tool remains available to abort/reset the horror state and restore the backed-up wallpaper and saved desktop/window positions.
- This package was checked statically; the PowerShell helper, wallpaper/audio behavior, and browser closure still need verification on a Windows machine.

LINUX ALPHA PORT
----------------
The separate JasperBrowser-Lite-Linux-v0.1.0 package is an early user-local port. It uses the installed Firefox-family browser and Python 3; it does not alter system Firefox or the Windows package. Wallpaper, cursor, panel/taskbar and desktop icon integration varies by Linux desktop and is not yet equivalent to the Windows build.
