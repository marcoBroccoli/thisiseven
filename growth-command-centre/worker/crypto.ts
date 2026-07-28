import type { Env } from "./env";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function bytesToBase64(value: Uint8Array): string {
  return btoa(String.fromCharCode(...value));
}

function arrayBuffer(value: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(value.byteLength);
  copy.set(value);
  return copy.buffer;
}

async function encryptionKey(env: Env): Promise<CryptoKey> {
  if (!env.CREDENTIAL_ENCRYPTION_KEY) throw new Error("Credential encryption has not been configured.");
  const raw = base64ToBytes(env.CREDENTIAL_ENCRYPTION_KEY);
  if (raw.byteLength !== 32) throw new Error("CREDENTIAL_ENCRYPTION_KEY must be a 32-byte base64 value.");
  return crypto.subtle.importKey("raw", arrayBuffer(raw), "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function encryptConnectionConfig(env: Env, value: unknown): Promise<string> {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, await encryptionKey(env), encoder.encode(JSON.stringify(value)))
  );
  return `v1.${bytesToBase64(nonce)}.${bytesToBase64(encrypted)}`;
}

export async function decryptConnectionConfig<T>(env: Env, ciphertext: string): Promise<T> {
  const [version, nonce, payload] = ciphertext.split(".");
  if (version !== "v1" || !nonce || !payload) throw new Error("Unknown encrypted connection format.");
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: base64ToBytes(nonce) },
    await encryptionKey(env),
    arrayBuffer(base64ToBytes(payload))
  );
  return JSON.parse(decoder.decode(decrypted)) as T;
}
