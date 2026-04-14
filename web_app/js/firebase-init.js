/* Firebase config — sama dengan rmsproapp/lib/firebase_options.dart (web) */
const firebaseConfig = {
  apiKey: 'AIzaSyCiCmpmEFnaZKx1OE84a2OgRDEn8E9Ulfk',
  authDomain: 'rmspro-2f454.firebaseapp.com',
  projectId: 'rmspro-2f454',
  storageBucket: 'rmspro-2f454.firebasestorage.app',
  messagingSenderId: '94407896005',
  appId: '1:94407896005:web:42a2ab858a0b24280379ac',
  databaseURL: 'https://rmspro-2f454-default-rtdb.asia-southeast1.firebasedatabase.app',
};

firebase.initializeApp(firebaseConfig);
window.db = firebase.firestore();
