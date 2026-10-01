// Explicit USB transport setup only. It never handles a session token or memory.
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export const PHONE_MEMORY_PORT = 47851;

export function connectPhoneMemoryUsb({ adbPath = 'adb', serial, execute = execFileSync } = {}) {
  const run = args => {
    try {
      return String(execute(adbPath, args, {
        encoding: 'utf8', timeout: 5000, maxBuffer: 64 * 1024, windowsHide: true,
      })).trim();
    } catch { throw new Error('phone_memory_usb_command_failed'); }
  };
  const devices = run(['devices']).split(/\r?\n/).slice(1)
    .map(line => line.trim().split(/\s+/))
    .filter(parts => parts[1] === 'device' && /^[A-Za-z0-9_-]+$/.test(parts[0]))
    .map(parts => parts[0]);
  if (serial !== undefined && (typeof serial !== 'string' || !/^[A-Za-z0-9_-]+$/.test(serial))) {
    throw new Error('phone_memory_invalid_usb_serial');
  }
  const selected = serial ?? (devices.length === 1 ? devices[0] : null);
  if (!selected || !devices.includes(selected)) throw new Error('phone_memory_select_one_authorized_usb_device');
  const local = `tcp:${PHONE_MEMORY_PORT}`;
  const remote = local;
  const mappings = run(['forward', '--list']).split(/\r?\n/)
    .filter(Boolean).map(line => line.trim().split(/\s+/));
  const occupied = mappings.filter(parts => parts[1] === local);
  if (occupied.length) {
    if (occupied.length !== 1 || occupied[0][0] !== selected || occupied[0][2] !== remote) {
      throw new Error('phone_memory_local_port_owned_by_another_forward');
    }
    return { transport_ready: true, created_forward: false, serial: selected, local_port: PHONE_MEMORY_PORT };
  }
  // --no-rebind protects any mapping appearing after the read-only check.
  run(['-s', selected, 'forward', '--no-rebind', local, remote]);
  return { transport_ready: true, created_forward: true, serial: selected, local_port: PHONE_MEMORY_PORT };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  try {
    const options = {};
    let consent = false;
    for (let i = 0; i < args.length; i++) {
      if (args[i] === '--connect') consent = true;
      else if (args[i] === '--serial' && args[i + 1]) options.serial = args[++i];
      else if (args[i] === '--adb' && args[i + 1]) options.adbPath = args[++i];
      else throw new Error('phone_memory_usb_invalid_arguments');
    }
    if (!consent) throw new Error('usage: node phone_memory_usb.mjs --connect [--serial USB_SERIAL] [--adb ADB_PATH]');
    if (!options.adbPath && process.env.LOCALAPPDATA) {
      const candidate = path.join(process.env.LOCALAPPDATA, 'Android', 'Sdk', 'platform-tools', 'adb.exe');
      if (existsSync(candidate)) options.adbPath = candidate;
    }
    console.log(JSON.stringify(connectPhoneMemoryUsb(options)));
  } catch (error) {
    console.log(JSON.stringify({ transport_ready: false, error: error.message }));
    process.exitCode = 1;
  }
}
