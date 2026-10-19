# Google Drive Picker with Search (Flutter: Web, Android, iOS)

Pick files from Google Drive and download their bytes.

- **Web:** native Google Picker (has its own search box, optional pre-filled query).
- **Android / iOS:** custom dialog with debounced search and infinite scroll.

---

## 1. Files

```
lib/.../google_drive/
  google_drive_picker_service.dart   # auth, search, download, upload
  drive_file_picker_dialog.dart      # mobile dialog UI with search bar
  google_drive_picker_stub.dart      # Android / iOS no-op implementation
  google_drive_picker_web.dart       # web JS interop
web/
  google_picker.js                   # Picker + Google Identity Services token
  index.html                         # script tags (section 4)
```

## 2. Dependencies (`pubspec.yaml`)

```yaml
dependencies:
  google_sign_in: ^7.0.0
  googleapis: ^13.0.0
  http: ^1.2.0
  get: ^4.6.6
```

Run `flutter pub get`.

---

## 3. Google Cloud setup (one time)

Open https://console.cloud.google.com and **select your project** (same project as Firebase).

### 3.1 Enable APIs
APIs & Services → Library → enable:
- **Google Drive API**
- **Google Picker API**

### 3.2 OAuth consent screen
APIs & Services → OAuth consent screen (Google Auth Platform):
- User type: External
- Add scope: `.../auth/drive.file`
- While in **Testing** mode, add your Google account(s) under **Test users**.

### 3.3 Web OAuth client  → gives you `_webClientId`
APIs & Services → Credentials → open the **Web application** client
(Firebase auto-creates one named "Web client (auto created by Google Service)").

- **Client ID** (top right of the page) = `_webClientId`
- The digits before the first dash = your **project number** = `_appId`
  (e.g. `81987916165-xxxx.apps.googleusercontent.com` → `81987916165`)
- **Authorized JavaScript origins** → add exactly (no trailing slash, no path):
  ```
  http://localhost:5000
  https://YOUR-PROJECT.firebaseapp.com
  https://your-production-domain.com
  ```
  Use `http` for localhost. `localhost` and `127.0.0.1` are different origins.
- Save. Changes can take 5 minutes to a few hours.

> You do **not** need the client secret anywhere. Never put it in Flutter code.

### 3.4 API key → used by the Picker (`setDeveloperKey`)
Credentials → Create credentials → API key, then edit it:
- **Application restrictions:** Websites → add
  `http://localhost:5000/*` and your production domains (`https://yourdomain.com/*`)
- **API restrictions:** Restrict key → **Google Picker API** (+ Google Drive API)
- Save.

### 3.5 Android OAuth client
Credentials → Create → OAuth client ID → **Android**
- Package name: your `applicationId`
- SHA-1: run `cd android && ./gradlew signingReport` and copy the debug SHA-1.
  Add the **release** and **Play App Signing** SHA-1 too before publishing.

### 3.6 iOS OAuth client
Credentials → Create → OAuth client ID → **iOS**
- Bundle ID: your iOS bundle identifier.

### 3.7 Data Access (scopes) in the console
Google Auth Platform → **Data Access** → **Add or remove scopes**, then add:

| Scope | Used for | Sensitivity |
|---|---|---|
| `https://www.googleapis.com/auth/drive.file` | Web Picker; files the user picks or the app creates | Non-sensitive (recommended) |

Click **Update**, then **Save**. If a scope is not listed here, Google may block the request or
omit it from the consent screen.

**Testing vs production**
- **Testing mode:** only listed Test users can sign in. No verification needed. Tokens for restricted
  scopes expire after 7 days.
- **Production:** with `drive.file` only, you can publish without a security review. With
  `drive.readonly`, submit the app for verification and provide a privacy policy, homepage and a demo video.

**Minimum-access options for mobile**
- Want the least access? Use `drive.file` on mobile too. The user then only sees files the app created or
  that the user opened with it, and search will not cover the rest of their Drive.
- Want true whole-Drive search? Keep `drive.readonly` and plan for verification.

---

## 4. Code configuration

### `google_drive_picker_service.dart` (top of file)

```dart
const _webScope = 'https://www.googleapis.com/auth/drive.file';
const _mobileScopes = [_webScope];

const _webClientId = 'YOUR_PROJECT_NUMBER-xxxxxxxx.apps.googleusercontent.com';
const _appId = 'YOUR_PROJECT_NUMBER';   // digits only, NOT the project name
```

### `web/google_picker.js`

```js
.setDeveloperKey('YOUR_NEW_API_KEY')
```

### `web/index.html` (inside `<head>`)

```html
<script src="https://apis.google.com/js/api.js"></script>
<script src="https://accounts.google.com/gsi/client"></script>
<script src="google_picker.js"></script>
```

Remove any `<meta name="google-signin-client_id" ...>` tag. It is not used and can
point at a different client ID than the Dart code.

---

## 5. Android setup

1. Add `google-services.json` to `android/app/` (download from Firebase Console).
2. Make sure the debug SHA-1 is registered (section 3.5).
3. `minSdkVersion` 21 or higher.
4. Nothing else is required: the service calls
   `GoogleSignIn.instance.initialize(serverClientId: _webClientId)`.

## 6. iOS setup

1. Add `GoogleService-Info.plist` to `ios/Runner` (via Xcode, "Copy items if needed").
2. Edit `ios/Runner/Info.plist`:

```xml
<key>GIDClientID</key>
<string>YOUR_IOS_CLIENT_ID.apps.googleusercontent.com</string>

<key>GIDServerClientID</key>
<string>YOUR_WEB_CLIENT_ID.apps.googleusercontent.com</string>

<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <!-- reversed iOS client ID -->
      <string>com.googleusercontent.apps.YOUR_IOS_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

3. Run `cd ios && pod install`.

---

## 7. Usage

```dart
final files = await GoogleDrivePickerService().openPicker(allowMultiple: true);

if (files != null) {
  for (final f in files) {
    print('${f.name}  ${f.mimeType}  ${f.bytes?.length} bytes');
  }
}

// Web only: pre-fill the picker's search box
await GoogleDrivePickerService().openPicker(initialQuery: 'invoice');

// Search programmatically (mobile / any platform with the Drive scope)
final page = await GoogleDrivePickerService().searchDriveFiles(query: 'report');
// next page: searchDriveFiles(query: 'report', pageToken: page.nextPageToken)

// Upload
final link = await GoogleDrivePickerService().uploadFile(
  fileName: 'hello.txt',
  bytes: Uint8List.fromList(utf8.encode('hello')),
  mimeType: 'text/plain',
);

// On logout
GoogleDrivePickerService().clearCache();
```

---

## 8. Running and testing

**Web** (use a fixed port so the registered origin always matches):
```
flutter run -d chrome --web-port=5000
```
Open exactly `http://localhost:5000`. VS Code: add `"args": ["--web-port=5000"]` in `launch.json`.

**Android:** `flutter run -d <device>` (SHA-1 must be registered).

**iOS:** `flutter run -d <simulator/device>` (needs the plist + URL scheme).

Quick test button:
```dart
ElevatedButton(
  onPressed: () async {
    final files = await GoogleDrivePickerService().openPicker();
    debugPrint(files?.map((f) => '${f.name} (${f.bytes?.length})').join(', '));
  },
  child: const Text('Pick from Drive'),
)
```

---

## 8.5 Data access process (runtime flow)

**Web**
1. User taps your button → `openPicker()`.
2. `requestDriveAccessToken()` runs Google Identity Services. First time, a Google popup asks for
   consent to `drive.file`; later it reuses the grant without a prompt.
3. An access token (about 1 hour) is returned and cached for `expires_in - 5 min`.
4. The Google Picker opens with that token. The user searches and selects files.
5. **Only the selected files** become accessible to your app (that is how `drive.file` works).
6. The app downloads each file with `GET /drive/v3/files/{id}?alt=media` (or `/export` for Google Docs/Sheets/Slides,
   converted to docx/xlsx/pptx) and returns `DrivePickedFile` with bytes.

**Android / iOS**
1. `openPicker()` → `GoogleSignIn` tries silent sign-in, then checks the scope silently.
2. If not yet granted, Google shows the sign-in and consent UI once.
3. The access token is cached. `DriveFilePickerDialog` calls `searchDriveFiles()` (Drive `files.list`) with the
   typed query, 30 results per page, loading more on scroll.
4. When the user taps a file, `getFileById()` downloads it and the dialog returns it.
5. If Drive returns 401 the token is refreshed once and the call is retried.

**What the app can and cannot see**

| | `drive.file` |
|---|---|
| Files the user picks in the Picker | Yes 
| Files the app created | Yes 
| Other files in the user's Drive (list/search) | No 
| Modify or delete existing files | Only the app's own 

**Data handling**
- Tokens live only in memory (never written to disk) and are cleared by `clearCache()`.
- File bytes are held in memory in `DrivePickedFile.bytes`; very large files can cause memory pressure.
  Consider a size check (`sizeBytes` from the web Picker, or `size` in the Drive fields) before downloading.
- Users can revoke access anytime at https://myaccount.google.com/permissions
- Publishing needs a privacy policy that says which Drive data you access, why, and how long you keep it.

---

## 9. How search works

- Mobile dialog: 400 ms debounce, stale-response protection, infinite scroll.
- Query sent to Drive: `trashed = false and mimeType != folder and name contains '<text>'`.
- `name contains` matches word **prefixes** ("inv" finds "Invoice", "voice" does not).
  For content search use `(name contains 'x' or fullText contains 'x')` in `searchDriveFiles`.
- **Scope matters:** `drive.file` only lets `files.list` see files your app created or
  opened, so search looks empty. `drive.readonly` searches the whole Drive but is a
  *restricted* scope (Google verification needed for public release).

---

## 10. Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `401 invalid_client` / "no registered origin" | Wrong client ID, or no origins on the client | Use the Web client ID from your project; add JS origins |
| `400 origin_mismatch` | Running origin not registered | Register the exact origin (`http://localhost:5000`), run with `--web-port=5000`, wait a few minutes, try incognito |
| "The API developer key is invalid" | Old/wrong API key, Picker API not enabled, bad referrer | New key in the same project, enable Picker API, referrer `http://localhost:5000/*`, hard refresh |
| "Access blocked: app not verified" / 403 access_denied | Consent screen in Testing | Add your account as a Test user |
| Picker opens but file download fails (404/403) | `_appId` wrong or Drive API not enabled | `_appId` = project number; enable Drive API |
| Mobile search shows no files | Using `drive.file` scope | Use `drive.readonly` in `_mobileScopes` |
| Android `ApiException: 10` / sign-in fails | SHA-1 or package name not registered | Add SHA-1 to Android OAuth client; add `serverClientId` |
| iOS crashes at sign-in | Missing URL scheme / `GIDClientID` | Fix `Info.plist` (section 6) |
| Popup blocked on web | Token request not triggered by a click | Call `openPicker()` directly from a button's `onPressed` |
| Still failing after changes | Propagation / cache | Wait 5-30 min, incognito window, Cmd+Shift+R |

---

## 11. Security notes

- Restrict the API key by HTTP referrer and by API.
- Never commit or ship the OAuth **client secret**; this code does not use it.
- Delete unused client secrets in Cloud Console.
- Call `clearCache()` on logout.
- Keys/IDs from a previous project should be rotated if they were shared publicly.