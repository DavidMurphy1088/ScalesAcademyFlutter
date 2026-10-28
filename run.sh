#!/bin/bash
# Run SA Flutter on a device.
#   ./run.sh        shows the menu
#   ./run.sh 1      runs straight on Android (2 = web, 3 = iOS)
# While running: r = hot reload, R = hot restart, q = quit.

ANDROID_ID="R83YC0ACRMZ"                  # Samsung SM A075F (plug in by USB, unlocked)
IOS_ID="00008110-000A4D263E40A01E"        # DMurphy's iPhone

cd "$(dirname "$0")" || exit 1

choice="$1"
if [ -z "$choice" ]; then
  echo "SA Flutter - run on:"
  echo "  1) Android (Samsung)"
  echo "  2) Web (Chrome)"
  echo "  3) iOS (iPhone)"
  echo "  q) Quit"
  printf "Choose 1, 2, 3 or q: "
  read -r choice
fi

case "$choice" in
  1) device="$ANDROID_ID"; label="Android (Samsung)" ;;
  2) device="chrome";      label="Web (Chrome)" ;;
  3) device="$IOS_ID";     label="iOS (iPhone)" ;;
  q|Q) echo "Bye."; exit 0 ;;
  *) echo "Please choose 1, 2, 3 or q."; exit 1 ;;
esac

echo "Running SA Flutter on $label..."
flutter pub get || exit 1
flutter run -d "$device"
