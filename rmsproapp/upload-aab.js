const { google } = require('googleapis');
const fs = require('fs');
const path = require('path');

const PACKAGE_NAME = 'com.rmspro';
const AAB_PATH = path.join(__dirname, 'build', 'app', 'outputs', 'bundle', 'release', 'app-release.aab');
const KEY_FILE = path.join(__dirname, 'play-store-key.json');
const TRACK = 'internal';

const TESTERS = [
  'profixkl@gmail.com',
  'dinhafiz94@gmail.com',
  'profixmobile7@gmail.com',
  'harishaikal252005@gmail.com',
  'Mohdrashdan0303@gmail.com',
  'zulhidayah944@gmail.com',
  'Amnistinyhouse@gmail.com',
  'Srtinyhousemy@gmail.com',
  'Beheqofi@gmail.com',
  'Kopitiamaboh@gmail.com',
  'profixmobile001@gmail.com',
  'Luqmanrizuhan03@gmail.com',
];

async function main() {
  const auth = new google.auth.GoogleAuth({
    keyFile: KEY_FILE,
    scopes: ['https://www.googleapis.com/auth/androidpublisher'],
  });

  const publisher = google.androidpublisher({ version: 'v3', auth });

  console.log('→ Creating edit for package:', PACKAGE_NAME);
  let edit;
  try {
    const res = await publisher.edits.insert({ packageName: PACKAGE_NAME });
    edit = res.data;
    console.log('  Edit ID:', edit.id);
  } catch (e) {
    console.error('✗ Failed to create edit:', e.message);
    if (e.response?.data) console.error(JSON.stringify(e.response.data, null, 2));
    process.exit(1);
  }

  console.log('→ Uploading AAB:', AAB_PATH);
  console.log('  Size:', (fs.statSync(AAB_PATH).size / 1024 / 1024).toFixed(2), 'MB');
  let bundle;
  try {
    const res = await publisher.edits.bundles.upload({
      packageName: PACKAGE_NAME,
      editId: edit.id,
      media: {
        mimeType: 'application/octet-stream',
        body: fs.createReadStream(AAB_PATH),
      },
    });
    bundle = res.data;
    console.log('  Uploaded versionCode:', bundle.versionCode);
  } catch (e) {
    console.error('✗ Upload failed:', e.message);
    if (e.response?.data) console.error(JSON.stringify(e.response.data, null, 2));
    process.exit(1);
  }

  console.log('→ Assigning to track:', TRACK);
  try {
    await publisher.edits.tracks.update({
      packageName: PACKAGE_NAME,
      editId: edit.id,
      track: TRACK,
      requestBody: {
        track: TRACK,
        releases: [{
          status: 'completed',
          versionCodes: [String(bundle.versionCode)],
          releaseNotes: [{ language: 'en-US', text: 'Initial internal test release.' }],
        }],
      },
    });
    console.log('  Track updated.');
  } catch (e) {
    console.error('✗ Track update failed:', e.message);
    if (e.response?.data) console.error(JSON.stringify(e.response.data, null, 2));
    process.exit(1);
  }

  console.log('→ Committing edit...');
  try {
    await publisher.edits.commit({ packageName: PACKAGE_NAME, editId: edit.id });
    console.log('✓ Committed successfully.');
  } catch (e) {
    console.error('✗ Commit failed:', e.message);
    if (e.response?.data) console.error(JSON.stringify(e.response.data, null, 2));
    process.exit(1);
  }

  console.log('\n→ Note: Tester emails must be added manually via Play Console,');
  console.log('  or by creating/editing an email list. Testers to add:');
  TESTERS.forEach(t => console.log('  -', t));
}

main().catch(e => { console.error(e); process.exit(1); });
