import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { ref, set, get, update, serverTimestamp } from 'firebase/database';
import { ref as objectRef, uploadBytes, getBytes, deleteObject } from 'firebase/storage';
let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-aquasense',
    database: { host: '127.0.0.1', port: 9000, rules: await readFile(new URL('../database.rules.json', import.meta.url), 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: await readFile(new URL('../storage.rules', import.meta.url), 'utf8') },
  });
});
beforeEach(async () => { await env.clearDatabase(); await env.clearStorage(); });
after(async () => { await env?.cleanup(); });
const human = (uid = 'user', role) => env.authenticatedContext(uid, { email_verified: true, ...(role ? { role } : {}) });
const device = (uid = 'sensor1') => env.authenticatedContext(uid, { role: 'ph_device' }).database();
const reading = (deviceId = 'sensor1') => ({ deviceId, ph: 6.5, adcRaw: 2048, measuredVoltage: 1.65, timestamp: serverTimestamp() });
const analysis = (createdBy = 'inspector1') => ({ sampleId: 'sample1', storagePath: 'samples/sample1/images/gills.jpg', meanHue: 10, classification: 'Fresh', timestamp: serverTimestamp(), createdBy, meanSaturation: 0.8, meanValue: 0.8, redFraction: 0.9, usableFraction: 1 });

test('anonymous, unverified and device users cannot read shared records', async () => {
  for (const db of [env.unauthenticatedContext().database(), env.authenticatedContext('unverified', {email_verified: false}).database(), device()]) {
    await assertFails(get(ref(db, 'readings')));
    await assertFails(get(ref(db, 'telemetry')));
    await assertFails(get(ref(db, 'analyses')));
    await assertFails(set(ref(db, 'FishSamples/current_reading'), reading()));
  }
  await assertSucceeds(get(ref(human().database(), 'readings')));
});
test('registration saves an owner-bound profile without roles or privileges', async () => {
  const db = env.authenticatedContext('newUser', { email: 'new@example.com' }).database();
  await assertSucceeds(set(ref(db, 'users/newUser'), { displayName: 'New User', email: 'new@example.com', createdAt: serverTimestamp() }));
  await assertFails(update(ref(db, 'users/newUser'), { role: 'admin' }));
  await assertFails(set(ref(db, 'users/someoneElse'), { displayName: 'Other', email: 'new@example.com', createdAt: serverTimestamp() }));
  const other = env.authenticatedContext('otherNew', { email: 'other@example.com' }).database();
  await assertFails(set(ref(other, 'users/otherNew'), { displayName: 'Other', email: 'spoof@example.com', createdAt: serverTimestamp() }));
  await assertFails(set(ref(other, 'users/otherNew'), { displayName: 'Other', email: 'other@example.com', requestedRole: 'Inspector', createdAt: serverTimestamp() }));
  await assertFails(get(ref(human('other').database(), 'users/newUser')));
  await assertFails(set(ref(human('newUser').database(), 'analyses/new'), analysis('newUser')));
});
test('device can atomically publish its live reading and append history', async () => {
  const db = device();
  await assertSucceeds(update(ref(db), { 'telemetry/sensor1': reading(), 'readings/record1': reading() }));
  await assertSucceeds(get(ref(human().database(), 'telemetry/sensor1')));
  await assertFails(set(ref(db, 'readings/record1'), reading()));
  await assertFails(set(ref(db, 'readings/record1'), null));
  await assertFails(set(ref(db, 'telemetry/anotherDevice'), reading()));
  await assertFails(set(ref(db, 'readings/spoof'), reading('anotherDevice')));
  await assertFails(set(ref(human('user', 'inspector').database(), 'readings/manual'), reading('user')));
});
test('malformed, stale or unexpected telemetry is denied', async () => {
  for (const [i, patch] of [{ph: 14.1}, {ph: -1}, {adcRaw: 4095}, {adcRaw: 0}, {measuredVoltage: 4}, {timestamp: 1}, {extra: true}].entries()) {
    await assertFails(set(ref(device(), `readings/bad${i}`), {...reading(), ...patch}));
  }
});
test('only approved inspectors can create immutable attributed analyses', async () => {
  const db = human('inspector1', 'inspector').database();
  await assertSucceeds(set(ref(db, 'analyses/a1'), analysis()));
  await assertFails(set(ref(db, 'analyses/a1'), analysis()));
  await assertFails(set(ref(db, 'analyses/a2'), analysis('other')));
  await assertFails(set(ref(db, 'analyses/a3'), {...analysis(), storagePath: 'samples/other/images/gills.jpg'}));
  await assertFails(set(ref(db, 'analyses/a4'), {...analysis(), meanSaturation: 2}));
  await assertFails(set(ref(human('vendor1', 'vendor').database(), 'analyses/a5'), analysis('vendor1')));
});
test('storage requires approved ownership, JPEG and verified readers', async () => {
  const storage = human('inspector1', 'inspector').storage();
  const path = 'samples/sample1/images/gills.jpg';
  const metadata = { contentType: 'image/jpeg', customMetadata: { ownerUid: 'inspector1' } };
  await assertSucceeds(uploadBytes(objectRef(storage, path), new Uint8Array([255,216,255,217]), metadata));
  await assertSucceeds(getBytes(objectRef(human().storage(), path)));
  await assertFails(getBytes(objectRef(env.unauthenticatedContext().storage(), path)));
  await assertFails(uploadBytes(objectRef(human('vendor1', 'vendor').storage(), 'samples/sample1/images/vendor.jpg'), new Uint8Array([1]), { ...metadata, customMetadata: {ownerUid: 'vendor1'} }));
  await assertFails(uploadBytes(objectRef(storage, 'samples/sample1/images/bad.jpg'), new Uint8Array([1]), { ...metadata, contentType: 'text/plain' }));
  await assertFails(uploadBytes(objectRef(storage, 'samples/sample1/images/spoof.jpg'), new Uint8Array([1]), { ...metadata, customMetadata: {ownerUid: 'other'} }));
  await assertFails(deleteObject(objectRef(human('other', 'inspector').storage(), path)));
  await assertSucceeds(deleteObject(objectRef(storage, path)));
});
