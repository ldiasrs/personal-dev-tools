import CryptoJS from "crypto-js";
import dotenv from "dotenv";
dotenv.config();

// Usage: node src/crypt/crypt.js <encrypt|decrypt> <value>
// The passphrase comes from CRYPT_KEY (env or .env). Output is CryptoJS AES
// passphrase format, so values encrypted elsewhere with CryptoJS decrypt here.
const [mode, value] = process.argv.slice(2);

if (!["encrypt", "decrypt"].includes(mode) || !value) {
  console.error("Usage: crypt.js <encrypt|decrypt> <value>");
  process.exit(1);
}

const key = process.env.CRYPT_KEY;
if (!key) {
  console.error("CRYPT_KEY is required (env var or .env)");
  process.exit(1);
}

const result =
  mode === "encrypt"
    ? CryptoJS.AES.encrypt(value, key).toString()
    : CryptoJS.AES.decrypt(value, key).toString(CryptoJS.enc.Utf8);

if (!result) {
  console.error("Decryption produced no output: wrong key or corrupted value");
  process.exit(1);
}

console.log(result);
