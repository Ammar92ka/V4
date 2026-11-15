#!/usr/bin/env python3
"""يضبط توقيع نسخة الإصدار في android/app/build.gradle بمفتاح ثابت.

لماذا: flutter create يوقّع نسخة الإصدار بمفتاح debug يتولد من جديد على كل جهاز بناء،
فلا يتثبت APK جديد فوق القديم وتضيع اللعبة المحفوظة. المفتاح الثابت يحل ذلك.
"""
import pathlib
import re
import sys

gradle = pathlib.Path("android/app/build.gradle")
if not gradle.exists():
    sys.exit("لم أجد android/app/build.gradle (هذا السكربت يدعم Flutter 3.22 بصيغة Groovy)")

text = gradle.read_text(encoding="utf-8")
if "signingConfigs.release" in text:
    print("التوقيع مضبوط مسبقا")
    sys.exit(0)

block = '''    signingConfigs {
        release {
            storeFile file("../../signing/ottoman.p12")
            storeType "pkcs12"
            storePassword System.getenv("KEYSTORE_PASSWORD") ?: "ottoman-game-1800"
            keyAlias System.getenv("KEY_ALIAS") ?: "ottoman"
            keyPassword System.getenv("KEY_PASSWORD") ?: "ottoman-game-1800"
        }
    }

'''
new, n1 = re.subn(r"(\n\s*)buildTypes\s*\{", lambda m: "\n" + block + m.group(1).lstrip("\n") + "buildTypes {", text, count=1)
new, n2 = re.subn(r"signingConfig\s*=?\s*signingConfigs\.debug", "signingConfig signingConfigs.release", new)
if n1 != 1 or n2 < 1:
    sys.exit(f"تعذر تعديل build.gradle (buildTypes={n1}, signingConfig={n2})")
gradle.write_text(new, encoding="utf-8")
print("تم ضبط التوقيع الثابت")
