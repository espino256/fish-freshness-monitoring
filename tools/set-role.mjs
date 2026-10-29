// Trusted workstation/server only. ADC credentials never go in Flutter or firmware.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
const [uid, role] = process.argv.slice(2);
if (!uid || !['inspector', 'vendor', 'consumer', 'ph_device', 'admin'].includes(role)) {
  throw new Error('Usage: npm run role -- UID inspector|vendor|consumer|ph_device|admin');
}
if (!process.env.GOOGLE_CLOUD_PROJECT) throw new Error('Set GOOGLE_CLOUD_PROJECT first.');
initializeApp({ credential: applicationDefault(), projectId: process.env.GOOGLE_CLOUD_PROJECT });
const user = await getAuth().getUser(uid);
await getAuth().setCustomUserClaims(uid, { ...user.customClaims, role });
console.log('Role assigned. Refresh the user session; device accounts reauthenticate on restart.');
