#!/usr/bin/env node

import { Client } from "ssh2";
import { readFileSync, existsSync } from "fs";
import path from "node:path";

// Usage: npm run sftp-test [-- <file-to-upload>]
// With no file, a small generated PDF-like buffer is uploaded instead.
const filePath = process.argv[2];
const SFTP_PORT = Number(process.env.SFTP_PORT || 2222);

const loadContent = () => {
  if (!filePath) {
    return { name: "sftp-test.pdf", content: Buffer.from("%PDF-1.4\n% sftp-server test upload\n%%EOF\n") };
  }
  if (!existsSync(filePath)) {
    console.log("❌ File not found at:", filePath);
    process.exit(1);
  }
  return { name: path.basename(filePath), content: readFileSync(filePath) };
};

const { name, content } = loadContent();
const client = new Client();

console.log("🧪 Testing SFTP server buffer handling...");

client.on("ready", () => {
  console.log("✅ SSH connection established");

  client.sftp((err, sftp) => {
    if (err) {
      console.log("❌ SFTP error:", err.message);
      client.end();
      return;
    }

    console.log("✅ SFTP session started");
    console.log(`📄 Uploading ${name} (${content.length} bytes)`);

    const writeStream = sftp.createWriteStream(name);

    writeStream.on("error", (err) => {
      console.log("❌ Write stream error:", err.message);
      client.end();
    });

    // ssh2 destroys the stream in _final, so on Node 22 'finish' never fires;
    // 'close' is emitted once the server acknowledges the CLOSE.
    writeStream.on("close", () => {
      console.log("✅ File uploaded successfully");
      console.log("📊 Buffer length:", content.length, "bytes");
      console.log("📊 File size (KB):", (content.length / 1024).toFixed(2), "KB");
      console.log("📄 Header:", content.slice(0, 4).toString());
      client.end();
    });

    writeStream.write(content);
    writeStream.end();
  });
});

client.on("error", (err) => {
  console.log("❌ Client error:", err.message);
});

client.connect({
  host: "localhost",
  port: SFTP_PORT,
  username: process.env.SFTP_USER || "testuser",
  password: process.env.SFTP_PASS || "testpass",
});
