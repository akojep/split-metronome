SPLIT METRONOME  -  how to use this folder
==========================================

1. Copy this whole folder to any Windows computer.
2. Double-click  START METRONOME.bat
3. If Windows Firewall asks, click "Allow access" (Private networks).
4. On your phone, connected to the SAME Wi-Fi as that computer, open

       http://metro.local:8765

   (the black window shows the exact link; the number at the end can
   change if 8765 is busy on that computer)
5. Keep the black window open while you use the app.
   Close it (or press Ctrl+C) to stop.

If the name does not open
- The window also shows a plain address like http://192.168.1.23:8765
  Use that instead.
- The name works on iPhone, iPad, Mac and most Android phones.
  Some Android phones do not do ".local" names; use the address.
- Check both devices are on the same Wi-Fi, the firewall allowed
  "Windows PowerShell", and no VPN is blocking local traffic.

Tips
- In Safari use Share > Add to Home Screen to get an app icon.
- Nothing is installed on the computer. server.ps1 is a small
  PowerShell script that serves the files in this folder and
  answers the name "metro.local" on the local network.
- To change the name, edit the first line of server.ps1 ($name).

Files
- index.html        the app
- guide-voices.js   the voice guide clips
- manifest.json, sw.js, icon-*.png   home-screen icon and offline support (offline needs https hosting)
- server.ps1, START METRONOME.bat    the launcher
- make_icons.py     only used to regenerate the icons, not needed to run
