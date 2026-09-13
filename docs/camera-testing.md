# Testing camera capture

The `Camera` row in the attachment bottom-sheet is wired to
`ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85)`.
It is only shown when
`kIsWeb || Platform.isAndroid || Platform.isIOS` (see `_cameraAvailable`
in `lib/ui/attachment_picker.dart`); on Windows / macOS / Linux the row
does not render at all.

There is **no offline unit test** for camera capture because
`image_picker` is a platform-channel plugin: on Flutter's test host it
throws `MissingPluginException` on every call. The full flow has to be
smoke-tested on a real target (or via the platform-specific mock hook
described at the end of this file).

## Common flow to verify (all platforms)

Whether you test on Android, iOS or web, walk through these steps:

1. Sign in as any user (e.g. `alice@rainbow-stub.local`, password
   `password`).
2. Open a 1:1 chat and tap the paperclip.
3. Tap **Camera**.
4. Grant the camera permission if prompted.
5. Take a photo and confirm.
6. Expected:
   - The bottom-sheet dismisses.
   - The chat scroll settles on a new image bubble that shows your
     photo (via `AuthedImage` which authenticates the download).
   - Open the same chat on a second signed-in device — the image
     round-trips over XMPP as a `<file xmlns="urn:rainbow:file:1">`
     attachment.
7. Also verify group chats: open a bubble, repeat 3–6.

## Android

### Prereqs

- Android SDK + emulator (or a physical device with USB debugging).
- `flutter doctor` clean for Android.
- The workspace currently does **not** ship an `android/` folder — you
  need to scaffold it once with `flutter create --platforms=android .`
  from `c:\www\flutter\rainbow_stub_consumer\`.

### Permissions

After scaffolding, image_picker generally launches the system camera
intent which handles its own runtime permission dialog, but on
**Android 13+** you also want to declare the following in
`android/app/src/main/AndroidManifest.xml` inside `<manifest>` (outside
`<application>`):

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
```

The `READ_MEDIA_IMAGES` permission covers the "Image" (gallery) tile
too.

### Point the emulator at the local stub

The emulator sees the host machine at `10.0.2.2`, not `localhost`.

- Start the stub with `chdir c:\www\dart\rainbow-stub; dart run bin/server.dart`.
- In `lib/config.dart` temporarily override `AppConfig.dev` so that
  `restBaseUrl` and `wsUrl` point at `https://10.0.2.2:8443` and
  `wss://10.0.2.2:8443/websocket`. Do NOT commit the override.
- The stub's self-signed cert is already `acceptSelfSignedCerts: true`
  on the client. If Android still refuses, add a
  `network_security_config.xml` with `<domain>10.0.2.2</domain>` as
  trust anchor.

### Run

```powershell
cd c:\www\flutter\rainbow_stub_consumer
& 'C:\flutter\flutter_windows_3.27.4-stable\flutter\bin\flutter.bat' devices
# copy an emulator id or a device id
& 'C:\flutter\flutter_windows_3.27.4-stable\flutter\bin\flutter.bat' run -d <deviceId>
```

Now walk the "Common flow" above. On the emulator the camera view is a
green rotating rectangle by default — that counts as a valid capture.

## iOS

### Prereqs

- macOS host (this can't be exercised from the current Windows dev box —
  either run from a Mac or use CI).
- Xcode installed, iOS simulator or a paired physical device.
- Scaffold: `flutter create --platforms=ios .`

### Permissions

In `ios/Runner/Info.plist` add:

```xml
<key>NSCameraUsageDescription</key>
<string>Rainbow needs the camera so you can take photos to send in
chats.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Rainbow needs your photo library so you can attach existing
images.</string>
```

The iOS simulator does not have a real camera — image_picker will
present a fake capture UI. For a full check you need a physical device.

### Run

Same as Android, but choose the iOS device with `-d`:

```
flutter devices
flutter run -d <ios-device-or-simulator-id>
```

Point at the stub the same way (Mac uses `localhost` on the simulator,
`<mac-lan-ip>` on a physical device).

## Web (Chrome / Edge)

image_picker on the web uses `<input type="file" accept="image/*"
capture="environment">` under the hood. On desktop browsers this
degrades to the OS file dialog; on mobile browsers it opens the camera.

### Run

```powershell
cd c:\www\flutter\rainbow_stub_consumer
& 'C:\flutter\flutter_windows_3.27.4-stable\flutter\bin\flutter.bat' run -d chrome
```

The stub's self-signed cert will trip Chrome's HSTS. Either accept the
warning at `https://localhost:8443` in a fresh tab first, or run the
stub behind a trusted local cert (mkcert).

Walk the common flow. On desktop Chrome the "Camera" tile will open
the file dialog (image_picker's web fallback); on a phone browser it
opens the camera app.

## Windows / macOS / Linux desktop

Not supported by image_picker's camera source. The **Camera** tile is
hidden by design (`_cameraAvailable` returns false). The "Image" tile
(gallery) still works everywhere via `file_picker`.

## Automated regression coverage

The picker itself doesn't have an offline test because platform
channels aren't available in `flutter_test`. If you want to guard the
sheet's return value, you can install a mock via
`ImagePickerPlatform.instance` in a widget test:

```dart
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

class _FakeImagePicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile.fromData(Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      name: 'test.jpg', mimeType: 'image/jpeg');
  // ... other overrides no-op
}

setUp(() {
  ImagePickerPlatform.instance = _FakeImagePicker();
});
```

That's a fair bit of boilerplate for a widget test, so we haven't
shipped one. Live smoke-testing (steps above) is the primary safety
net; the wire-level "image round-trips" behaviour is already covered
by Phase G attachment tests using synthetic bytes rather than the
camera.
