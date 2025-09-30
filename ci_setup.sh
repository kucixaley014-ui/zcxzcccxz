#!/usr/bin/env bash
set -e

echo "🔧 Ensuring Flutter project structure..."
if [ ! -d "android" ] || [ ! -d "ios" ]; then
  flutter create .
fi

echo "📦 Installing dependencies..."
flutter pub get

echo "🛠 Ensuring Android permissions..."
MANIFEST_FILE=android/app/src/main/AndroidManifest.xml
if [ -f "$MANIFEST_FILE" ]; then
python3 <<'PY'
import os, sys
mf = "android/app/src/main/AndroidManifest.xml"
with open(mf, encoding="utf-8") as f:
    txt = f.read()
if "android.permission.RECORD_AUDIO" not in txt:
    ins = ('<uses-permission android:name="android.permission.RECORD_AUDIO" />\n'
           '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />\n'
           '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n\n')
    i = txt.find("<application")
    if i != -1:
        txt = txt[:i] + ins + txt[i:]
        with open(mf, "w", encoding="utf-8") as f:
            f.write(txt)
        print("✔ Permissions inserted into", mf)
    else:
        print("⚠ <application> not found in manifest, skipping")
else:
    print("✔ Permissions already exist")
PY
fi

echo "🛠 Ensuring iOS Info.plist permissions..."
INFO_PLIST=ios/Runner/Info.plist
if [ -f "$INFO_PLIST" ]; then
python3 <<'PY'
import os, sys
import xml.etree.ElementTree as ET
p = "ios/Runner/Info.plist"
tree = ET.parse(p)
root = tree.getroot()
dict_el = root.find("dict")
if dict_el is None:
    print("⚠ No <dict> found in Info.plist; skipping")
    sys.exit(0)
exists = False
elems = list(dict_el)
for i in range(0, len(elems)-1):
    if elems[i].tag == "key" and elems[i].text == "NSMicrophoneUsageDescription":
        exists = True
        break
if not exists:
    key_el = ET.Element("key"); key_el.text = "NSMicrophoneUsageDescription"
    str_el = ET.Element("string"); str_el.text = "Приложению нужен доступ к микрофону чтобы записывать голос"
    dict_el.append(key_el); dict_el.append(str_el)
    tree.write(p, encoding="utf-8", xml_declaration=True)
    print("✔ NSMicrophoneUsageDescription added to", p)
else:
    print("✔ NSMicrophoneUsageDescription already present")
PY
fi

echo "🔍 Running analyzer..."
flutter analyze

echo "🧪 Running tests..."
flutter test --coverage

echo "📦 Building release APK..."
flutter build apk --release
