const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFileSync, spawnSync} = require('node:child_process');
const test = require('node:test');

const repoRoot = path.resolve(__dirname, '..');
const script = path.join(repoRoot, 'scripts/download-actual-budget.js');
const nodePath = path.join(__dirname, 'fixtures/js-modules');

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'actualbudget-backup-test-'));
}

function runDownloader(args, env = {}) {
  return spawnSync(process.execPath, [script, ...args], {
    cwd: repoRoot,
    env: {
      ...process.env,
      NODE_PATH: nodePath,
      ...env,
    },
    encoding: 'utf8',
  });
}

function readZipJson(zipPath, entryName) {
  return JSON.parse(execFileSync('unzip', ['-p', zipPath, entryName], {encoding: 'utf8'}));
}

test('creates one zip per sync id with matching e2e passwords', () => {
  const root = makeTempDir();
  const dataDir = path.join(root, 'data');
  const destDir = path.join(root, 'backup');

  const result = runDownloader([
    '--syncIds=budget-one,budget-two',
    '--e2ePasswords=secret-one,',
    `--dataDir=${dataDir}`,
    `--destDir=${destDir}`,
    '--serverURL=https://actual.example.test',
    '--password=server-password',
    '--now=test',
  ]);

  assert.equal(result.status, 0, result.stderr || result.stdout);

  const first = readZipJson(path.join(destDir, 'backup.budget-one.test.zip'), 'budget.json');
  const second = readZipJson(path.join(destDir, 'backup.budget-two.test.zip'), 'budget.json');

  assert.deepEqual(first, {
    syncId: 'budget-one',
    e2ePassword: 'secret-one',
    serverURL: 'https://actual.example.test',
    password: 'server-password',
  });
  assert.equal(second.syncId, 'budget-two');
  assert.equal(second.e2ePassword, null);
  assert.deepEqual(fs.readdirSync(dataDir), []);
});

test('exits non-zero when any budget download fails', () => {
  const root = makeTempDir();
  const dataDir = path.join(root, 'data');
  const destDir = path.join(root, 'backup');

  const result = runDownloader(
    [
      '--syncIds=bad-budget,good-budget',
      '--e2ePasswords=bad-secret,good-secret',
      `--dataDir=${dataDir}`,
      `--destDir=${destDir}`,
      '--serverURL=https://actual.example.test',
      '--password=server-password',
      '--now=test',
    ],
    {
      ACTUAL_MOCK_FAIL_SYNC_ID: 'bad-budget',
    },
  );

  assert.equal(result.status, 1, result.stderr || result.stdout);
  assert.equal(fs.existsSync(path.join(destDir, 'backup.bad-budget.test.zip')), false);
  assert.equal(fs.existsSync(path.join(destDir, 'backup.good-budget.test.zip')), true);
});
