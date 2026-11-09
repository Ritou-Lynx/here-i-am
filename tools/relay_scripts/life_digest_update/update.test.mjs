import { test } from 'node:test';
import assert from 'node:assert/strict';
import { acceptedHash, hash, launcherPaths, logicalDate } from './update.mjs';
test('reads quoted Windows launcher paths with spaces and doubled VBS quotes', () => {
  const text = 'WScript.Run("cmd /c ""C:\\Program Files\\runtime\\node.exe"" ""C:\\Users\\Example\\life-digest\\tool-12345678\\tools\\life_digest\\life_digest_run.mjs"" --config ""config.json""", 0, True)';
  assert.deepEqual(launcherPaths(text), { node: 'C:\\Program Files\\runtime\\node.exe', runner: 'C:\\Users\\Example\\life-digest\\tool-12345678\\tools\\life_digest\\life_digest_run.mjs' });
  assert.throws(() => launcherPaths('unrelated launcher'), /launcher_unrecognized/);
});
test('date agrees with the 04:00 Shanghai boundary', () => {
  assert.equal(logicalDate(Date.parse('2026-11-09T03:59:00+08:00')), '2026-11-08');
  assert.equal(logicalDate(Date.parse('2026-11-09T04:00:00+08:00')), '2026-11-09');
});
test('only known module versions accepted and newline conversion is harmless', () => {
  assert.equal(acceptedHash('447bcbc2b022767827cbaabbb86d0aed435ad1c45a91a67ef6950cb657190b7f'), true);
  assert.equal(acceptedHash('unknown'), false);
  assert.equal(hash(Buffer.from('a\r\nb')), hash(Buffer.from('a\nb')));
});
