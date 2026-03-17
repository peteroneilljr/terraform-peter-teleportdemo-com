<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!--
  macOS launchd agent for tbot (Teleport Machine ID daemon).

  Template — replace all YOUR_* placeholders before use:
    YOUR_CLUSTER_LABEL  — short label for this cluster, e.g. "mycluster"
                          Used in the plist Label and file paths.
    YOUR_USER           — your macOS username (output of: whoami)

  Install steps:
    1. Fill in the placeholders below and save to:
         ~/Library/LaunchAgents/com.YOUR_CLUSTER_LABEL.tbot.plist
    2. Create the log directory:
         mkdir -p ~/.tbot-YOUR_CLUSTER_LABEL/logs
    3. Load the agent:
         launchctl load ~/Library/LaunchAgents/com.YOUR_CLUSTER_LABEL.tbot.plist
    4. Check it started:
         launchctl list | grep tbot
         tail -f ~/.tbot-YOUR_CLUSTER_LABEL/logs/tbot.log
-->
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.YOUR_CLUSTER_LABEL.tbot</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/tbot</string>
        <string>start</string>
        <string>--config</string>
        <!-- Full path to your tbot.yaml — tilde expansion does not work here -->
        <string>/Users/YOUR_USER/.tbot-YOUR_CLUSTER_LABEL/tbot.yaml</string>
    </array>

    <!-- Start tbot when the agent loads (i.e. on login) -->
    <key>RunAtLoad</key>
    <true/>

    <!-- Keep tbot running; launchd will restart it if it exits -->
    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/Users/YOUR_USER/.tbot-YOUR_CLUSTER_LABEL/logs/tbot.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/YOUR_USER/.tbot-YOUR_CLUSTER_LABEL/logs/tbot.err.log</string>
</dict>
</plist>
