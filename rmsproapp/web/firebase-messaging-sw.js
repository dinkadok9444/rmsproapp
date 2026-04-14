importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCiCmpmEFnaZKx1OE84a2OgRDEn8E9Ulfk',
  appId: '1:94407896005:web:42a2ab858a0b24280379ac',
  messagingSenderId: '94407896005',
  projectId: 'rmspro-2f454',
  authDomain: 'rmspro-2f454.firebaseapp.com',
  storageBucket: 'rmspro-2f454.firebasestorage.app',
  databaseURL: 'https://rmspro-2f454-default-rtdb.asia-southeast1.firebasedatabase.app',
});

const messaging = firebase.messaging();
