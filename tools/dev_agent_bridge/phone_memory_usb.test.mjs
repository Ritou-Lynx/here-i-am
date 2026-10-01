import test from 'node:test';
import assert from 'node:assert/strict';
import { connectPhoneMemoryUsb } from './phone_memory_usb.mjs';

function transport(devices = 'USB1\tdevice', mappings = '') {
  const calls = [];
  const execute = (_binary, args, options) => {
    calls.push(args);
    assert.equal(options.windowsHide, true);
    assert.equal(options.timeout, 5000);
    if (args.join(' ') === 'devices') return `List of devices attached\n${devices}\n`;
    if (args.join(' ') === 'forward --list') return mappings;
    assert.deepEqual(args, ['-s', 'USB1', 'forward', '--no-rebind', 'tcp:47851', 'tcp:47851']);
    return '';
  };
  return { calls, execute };
}
test('creates only the exact selected USB forward', () => {
  const fake = transport();
  assert.equal(connectPhoneMemoryUsb(fake).created_forward, true);
  assert.equal(fake.calls.length, 3);
});
test('reuses but does not claim ownership of an existing matching forward', () => {
  const fake = transport(undefined, 'USB1 tcp:47851 tcp:47851');
  assert.equal(connectPhoneMemoryUsb(fake).created_forward, false);
  assert.equal(fake.calls.length, 2);
});
test('never replaces another device or target mapping', () => {
  for (const mapping of ['USB2 tcp:47851 tcp:47851', 'USB1 tcp:47851 tcp:8080']) {
    const fake = transport(undefined, mapping);
    assert.throws(() => connectPhoneMemoryUsb(fake), /owned_by_another/);
    assert.equal(fake.calls.length, 2);
  }
});
test('multiple devices require an explicit selection', () => {
  const fake = transport('USB1\tdevice\nUSB2\tdevice');
  assert.throws(() => connectPhoneMemoryUsb(fake), /select_one/);
  assert.equal(fake.calls.length, 1);
  assert.equal(connectPhoneMemoryUsb({ ...fake, serial: 'USB1' }).serial, 'USB1');
});
test('offline, unauthorized and network devices are not selected', () => {
  for (const device of ['USB1\toffline', 'USB1\tunauthorized', '127.0.0.1:5555\tdevice', '']) {
    const fake = transport(device);
    assert.throws(() => connectPhoneMemoryUsb(fake), /select_one/);
    assert.equal(fake.calls.length, 1);
  }
});
test('serial and command failures fail closed without raw output', () => {
  assert.throws(() => connectPhoneMemoryUsb({ ...transport(), serial: 'USB1;bad' }), /invalid_usb_serial/);
  const execute = () => { throw new Error('sensitive raw command diagnostics'); };
  assert.throws(() => connectPhoneMemoryUsb({ execute }), /^Error: phone_memory_usb_command_failed$/);
});
