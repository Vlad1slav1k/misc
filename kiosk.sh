#!/usr/bin/env bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

LOG=/var/log/kiosk-postinstall.log
exec > >(tee -a "$LOG") 2>&1

# Deployment user
KIOSK_USER="testuser"

if ! id -u "$KIOSK_USER" >/dev/null 2>&1; then
  echo "ERROR: user '$KIOSK_USER' not found"
  getent passwd || true
  exit 1
fi

HOME_DIR="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"
KIOSK_UID="$(id -u "$KIOSK_USER")"
KIOSK_GID="$(id -g "$KIOSK_USER")"

echo "=== kiosk-postinstall start $(date -Is) user=$KIOSK_USER home=$HOME_DIR ==="

# 1) Edge policy
install -d -m 0755 /etc/opt/edge/policies/managed
cat > /etc/opt/edge/policies/managed/policy.json <<'EOF'
{
  "URLBlocklist": ["*"],
  "URLAllowlist": [
    "https://businesscentral.dynamics.com",
    "https://*.businesscentral.dynamics.com",
    "https://dynamics.com",
    "https://*.dynamics.com",
    "https://login.microsoftonline.com",
    "https://microsoftonline.com",
    "https://*.microsoftonline.com",
    "https://*.microsoftonline-p.com",
    "https://msftauth.net",
    "https://*.msftauth.net",
    "https://msauth.net",
    "https://*.msauth.net",
    "https://*.msauthimages.net",
    "https://microsoft.com",
    "https://www.microsoft.com",
    "https://*.microsoft.com",
    "https://live.com",
    "https://*.live.com",
    "https://*.office.com",
    "https://*.office365.com",
    "https://*.windows.net",
    "https://*.azure.com",
    "https://*.sharepoint.com",
    "https://*.gstatic.com",
    "https://*.googleapis.com"
  ],
  "TranslateEnabled": false,
  "AddressBarEditingEnabled": false,
  "InPrivateModeAvailability": 1,
  "HideFirstRunExperience": true
}
EOF

# ... keep your header and policy part unchanged ...

# 2) Kiosk launcher script (no nested heredocs inside)
install -d -m 0755 "$HOME_DIR/.local/bin"
cat > "$HOME_DIR/.local/bin/gnome-kiosk-script" <<'KIOSK_EOF'
#!/usr/bin/env bash
set -u
TIMEOUT=60
COUNTER=0
USER_PROFILE="/home/testuser/.edge-kiosk-profile"
URL="https://www.microsoft.com/en-us/dynamics-365/products/business-central/sign-in"

(
while true; do
  if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo "100"
    echo "# Мережа знайдена! Запуск..."
    sleep 2
    exit 0
  fi
  PROGRESS=$(( COUNTER * 100 / TIMEOUT ))
  echo "$PROGRESS"
  echo "# Очікування мережі: ${COUNTER}с з ${TIMEOUT}с..."
  sleep 1
  COUNTER=$(( COUNTER + 1 ))
  if [ "$COUNTER" -gt "$TIMEOUT" ]; then
    exit 1
  fi
done
) | zenity --progress --title="Перевірка зв'язку" --text="Ініціалізація..." --percentage=0 --auto-close --no-cancel --width=420

microsoft-edge "$URL" \
  --app="$URL" \
  --start-maximized \
  --no-first-run \
  --no-default-browser-check \
  --password-store=basic \
  --user-data-dir="$USER_PROFILE" \
  --disable-features=Translate,EdgeWallet,EdgeShopping &

while pgrep -f microsoft-edge >/dev/null; do sleep 2; done
exec "$0"
KIOSK_EOF

chmod +x "$HOME_DIR/.local/bin/gnome-kiosk-script"
chown -R "$KIOSK_UID:$KIOSK_GID" "$HOME_DIR/.local"

# 3) GDM autologin
if ! grep -q '^\[daemon\]' /etc/gdm3/custom.conf; then
  printf '[daemon]\n' >> /etc/gdm3/custom.conf
fi
sed -i '/^[[:space:]]*#\?[[:space:]]*AutomaticLoginEnable[[:space:]]*=.*/d' /etc/gdm3/custom.conf
sed -i '/^[[:space:]]*#\?[[:space:]]*AutomaticLogin[[:space:]]*=.*/d' /etc/gdm3/custom.conf
sed -i "/^\[daemon\]/a AutomaticLoginEnable = true\nAutomaticLogin = ${KIOSK_USER}" /etc/gdm3/custom.conf

# 4) Autostart kiosk script
install -d -m 0755 "$HOME_DIR/.config/autostart"
cat > "$HOME_DIR/.config/autostart/gnome-kiosk.desktop" <<DESK_EOF
[Desktop Entry]
Type=Application
Name=GNOME Kiosk Script
Exec=$HOME_DIR/.local/bin/gnome-kiosk-script
X-GNOME-Autostart-enabled=true
Terminal=false
DESK_EOF
chown -R "$KIOSK_UID:$KIOSK_GID" "$HOME_DIR/.config"
