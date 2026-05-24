const api = require('@actual-app/api');
const path = require('path');
const fs = require('fs');
const {execFileSync} = require('child_process');
const argv = require('minimist')(process.argv.slice(2));

// Parse arguments using minimist
const dataDir = argv.dataDir || '/tmp/actual-download';
const destDir = argv.destDir || '/data/backup';
const serverURL = argv.serverURL || 'http://localhost:5006';
const password = argv.password || 'password';
const syncIdList = (argv.syncIds || '').split(',');
const e2ePasswords = (argv.e2ePasswords || '').split(',');
const now = argv.now || 'now';

console.log("📥 Starting download from", serverURL);
console.log("🗂 Sync IDs:", syncIdList);

function cleanDataDir() {
  fs.rmSync(dataDir, {recursive: true, force: true});
  fs.mkdirSync(dataDir, {recursive: true});
}

async function downloadBudget(syncId, e2ePassword) {
  const zipPath = path.join(destDir, `backup.${syncId}.${now}.zip`);
  let initialized = false;
  let downloaded = false;
  let hasError = false;

  console.log(`⬇️  Downloading budget ${syncId} -> ${zipPath}`);

  try {
    cleanDataDir();

    await api.init({dataDir, serverURL, password});
    initialized = true;

    await api.downloadBudget(syncId, e2ePassword ? {password: e2ePassword} : {});
    await api.getAccounts();
    downloaded = true;
    console.log(`✅ Budget ${syncId} downloaded successfully.`);
  } catch (err) {
    hasError = true;
    console.error(`❌ Failed to download ${syncId}:`, err);
  } finally {
    if (initialized) {
      try {
        await api.shutdown();
      } catch (err) {
        hasError = true;
        console.error(`❌ Failed to shutdown Actual API for ${syncId}:`, err);
      }
    }
  }

  if (downloaded) {
    try {
      execFileSync('zip', ['-r', zipPath, '.'], {cwd: dataDir, stdio: 'inherit'});
      console.log(`📦 Created zip: ${zipPath}`);
    } catch (err) {
      hasError = true;
      console.error(`❌ Failed to create zip for ${syncId}:`, err);
    }
  }

  cleanDataDir();

  return !hasError;
}

async function main() {
  fs.mkdirSync(destDir, {recursive: true});

  let hasError = false;

  for (let i = 0; i < syncIdList.length; i++) {
    const syncId = syncIdList[i];
    if (!syncId) continue;

    const e2ePassword = e2ePasswords[i] || null;
    const downloaded = await downloadBudget(syncId, e2ePassword);

    if (!downloaded) {
      hasError = true;
    }
  }

  if (hasError) {
    console.error("❌ One or more downloads failed.");
    process.exitCode = 1;
    return;
  }

  console.log("🎉 All downloads completed!");
}

main().catch((err) => {
  console.error("❌ Fatal download error:", err);
  process.exitCode = 1;
});
