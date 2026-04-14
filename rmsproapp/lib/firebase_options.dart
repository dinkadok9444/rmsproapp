import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCiCmpmEFnaZKx1OE84a2OgRDEn8E9Ulfk',
    appId: '1:94407896005:web:42a2ab858a0b24280379ac',
    messagingSenderId: '94407896005',
    projectId: 'rmspro-2f454',
    authDomain: 'rmspro-2f454.firebaseapp.com',
    storageBucket: 'rmspro-2f454.firebasestorage.app',
    databaseURL: 'https://rmspro-2f454-default-rtdb.asia-southeast1.firebasedatabase.app',
  );

  // ──────────────────────────────��───────────────
  // Firebase config SAMA dengan web app anda
  // Anda perlu tambah Android & iOS app di Firebase Console
  // kemudian update values di bawah dengan yang betul
  // ──────────────────────────────────────────────
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCiCmpmEFnaZKx1OE84a2OgRDEn8E9Ulfk',
    appId: '1:94407896005:android:201411fafcbd26a40379ac',
    messagingSenderId: '94407896005',
    projectId: 'rmspro-2f454',
    storageBucket: 'rmspro-2f454.firebasestorage.app',
    databaseURL: 'https://rmspro-2f454-default-rtdb.asia-southeast1.firebasedatabase.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDnlwMQRvqmHFttUcv5YNUpYZKVWTVW_4Y',
    appId: '1:94407896005:ios:45d50e9476b3dfa30379ac',
    messagingSenderId: '94407896005',
    projectId: 'rmspro-2f454',
    storageBucket: 'rmspro-2f454.firebasestorage.app',
    databaseURL: 'https://rmspro-2f454-default-rtdb.asia-southeast1.firebasedatabase.app',
    iosBundleId: 'com.rmspro.ios',
  );
}
