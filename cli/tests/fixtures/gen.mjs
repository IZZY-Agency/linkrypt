// cli/tests/fixtures/gen.mjs
// Run with: node cli/tests/fixtures/gen.mjs > cli/tests/fixtures/vectors.json

import { webcrypto } from 'node:crypto';
const subtle = webcrypto.subtle;

const toHex = (b) => [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, '0')).join('');

const vectors = [];

async function aesEncrypt(keyHex, ivHex, ptHex) {
  const key = await subtle.importKey(
    'raw',
    Buffer.from(keyHex, 'hex'),
    { name: 'AES-GCM' },
    false,
    ['encrypt'],
  );
  const ct = await subtle.encrypt(
    { name: 'AES-GCM', iv: Buffer.from(ivHex, 'hex') },
    key,
    Buffer.from(ptHex, 'hex'),
  );
  return toHex(ct);
}

// 1) AES-GCM zero key, zero IV, "hello"
vectors.push({
  name: 'aes_zero_hello',
  key:  '0'.repeat(64),
  iv:   '0'.repeat(24),
  pt:   Buffer.from('hello').toString('hex'),
  ct:   await aesEncrypt('0'.repeat(64), '0'.repeat(24), Buffer.from('hello').toString('hex')),
});

// 2) AES-GCM with random key/iv (frozen)
const key2 = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const iv2  = '101112131415161718191a1b';
const pt2  = Buffer.from('the rain in spain falls mainly on the plain').toString('hex');
vectors.push({
  name: 'aes_random_phrase',
  key: key2, iv: iv2, pt: pt2,
  ct: await aesEncrypt(key2, iv2, pt2),
});

// 3) AES-GCM empty plaintext (just the 16-byte tag)
vectors.push({
  name: 'aes_empty',
  key: '0'.repeat(64),
  iv:  '0'.repeat(24),
  pt:  '',
  ct:  await aesEncrypt('0'.repeat(64), '0'.repeat(24), ''),
});

// 4) PBKDF2-SHA256, 600_000 iter
async function pbkdf2(passphrase, saltHex) {
  const mat = await subtle.importKey(
    'raw',
    new TextEncoder().encode(passphrase),
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  const bits = await subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt: Buffer.from(saltHex, 'hex'), iterations: 600_000 },
    mat,
    256,
  );
  return toHex(bits);
}

vectors.push({
  name: 'pbkdf2_chbs',
  passphrase: 'correct horse battery staple',
  salt: '0102030405060708090a0b0c0d0e0f10',
  out:  await pbkdf2('correct horse battery staple', '0102030405060708090a0b0c0d0e0f10'),
});

// 5) PBKDF2 with unicode passphrase
vectors.push({
  name: 'pbkdf2_unicode',
  passphrase: 'café 🦀 password',
  salt: 'a1a2a3a4a5a6a7a8a9aaabacadaeafb0',
  out:  await pbkdf2('café 🦀 password', 'a1a2a3a4a5a6a7a8a9aaabacadaeafb0'),
});

console.log(JSON.stringify(vectors, null, 2));
