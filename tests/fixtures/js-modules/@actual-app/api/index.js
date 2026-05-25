const fs = require('node:fs');
const path = require('node:path');

let initOptions = null;

async function init(options) {
  initOptions = options;
  fs.mkdirSync(options.dataDir, {recursive: true});
}

async function downloadBudget(syncId, options = {}) {
  if (process.env.ACTUAL_MOCK_FAIL_SYNC_ID === syncId) {
    throw new Error(`mock download failed for ${syncId}`);
  }

  if (!initOptions) {
    throw new Error('Actual API mock was not initialized');
  }

  fs.writeFileSync(
    path.join(initOptions.dataDir, 'budget.json'),
    JSON.stringify(
      {
        syncId,
        e2ePassword: options.password || null,
        serverURL: initOptions.serverURL,
        password: initOptions.password,
      },
      null,
      2,
    ),
  );
  fs.mkdirSync(path.join(initOptions.dataDir, 'accounts'), {recursive: true});
  fs.writeFileSync(path.join(initOptions.dataDir, 'accounts/list.json'), JSON.stringify([{id: 'account-1'}]));
}

async function getAccounts() {
  return [{id: 'account-1'}];
}

async function shutdown() {
  initOptions = null;
}

module.exports = {
  init,
  downloadBudget,
  getAccounts,
  shutdown,
};
