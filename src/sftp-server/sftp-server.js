#!/usr/bin/env node

import pkg from "ssh2";
const { Server } = pkg;
import {
  createReadStream,
  createWriteStream,
  existsSync,
  mkdirSync,
  statSync,
  readFileSync,
} from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { execFileSync } from "child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Configuration
const PORT = Number(process.env.SFTP_PORT || 2222);
const UPLOADS_DIR = process.env.SFTP_UPLOADS_DIR || join(__dirname, "uploads");
const HOST_KEY_PATH = process.env.SFTP_HOST_KEY || join(__dirname, "keys", "host_key");

// Ensure uploads directory exists
if (!existsSync(UPLOADS_DIR)) {
  mkdirSync(UPLOADS_DIR, { recursive: true });
}

// Each machine gets its own host key; it is never committed.
if (!existsSync(HOST_KEY_PATH)) {
  mkdirSync(dirname(HOST_KEY_PATH), { recursive: true });
  execFileSync("ssh-keygen", ["-t", "rsa", "-b", "4096", "-m", "PEM", "-N", "", "-q", "-f", HOST_KEY_PATH]);
  console.log(`🔑 Generated new host key: ${HOST_KEY_PATH}`);
}

// Test credentials
const TEST_USER = process.env.SFTP_USER || "testuser";
const TEST_PASS = process.env.SFTP_PASS || "testpass";

console.log("🚀 Starting SFTP Test Server...");
console.log(`📁 Uploads directory: ${UPLOADS_DIR}`);
console.log(`🔑 Host key: ${HOST_KEY_PATH}`);
console.log(`👤 Test credentials: ${TEST_USER} / ${TEST_PASS}`);
console.log(`🌐 Listening on port ${PORT}`);
console.log(`📄 Ready to receive PDF files and other documents`);
console.log(`📊 Enhanced buffer logging enabled for file transfers`);
console.log("=====================================");

const server = new Server(
  {
    hostKeys: [readFileSync(HOST_KEY_PATH)],
  },
  async (client) => {
    console.log(`\n🔌 New client connection`);

    // Add error handling for the client
    client.on("error", (err) => {
      console.log(`❌ Client connection error:`, err.message);
    });

    client.on("authentication", async (ctx) => {
      console.log(
        `🔐 Authentication attempt: ${ctx.method} for user '${ctx.username}'`
      );

      if (ctx.method === "password") {
        if (ctx.username === TEST_USER && ctx.password === TEST_PASS) {
          console.log("✅ Authentication successful");
          ctx.accept();
        } else {
          console.log("❌ Authentication failed - invalid credentials");
          ctx.reject();
        }
      } else {
        console.log("❌ Authentication failed - only password auth supported");
        ctx.reject();
      }
    });

    client.on("ready", async () => {
      const remoteAddress =
        client.connection?.remoteAddress ||
        client.connection?.socket?.remoteAddress ||
        "unknown";
      console.log(`✅ Client authenticated: ${client.username}`);
      console.log(`🔗 Connection from: ${remoteAddress}`);
      console.log(`📊 Connection details:`, {
        remoteAddress: client.connection?.remoteAddress,
        socketRemoteAddress: client.connection?.socket?.remoteAddress,
        remotePort: client.connection?.remotePort,
        localAddress: client.connection?.localAddress,
        localPort: client.connection?.localPort,
      });

      client.on("session", async (accept, reject) => {
        const session = accept();

        session.on("sftp", async (accept, reject) => {
          console.log("📂 SFTP subsystem requested");
          const sftp = accept();

          // Track file operations and buffer lengths
          const openFiles = new Map();

          // Helper function to convert buffer to string for consistent comparison
          const bufferToString = (buffer) => buffer.toString("hex");

          sftp.on("OPEN", async (reqid, filename, flags, attrs) => {
            console.log(`📖 OPEN request: ${filename} (flags: ${flags})`);

            const fullPath = join(UPLOADS_DIR, filename);
            const dir = dirname(fullPath);

            try {
              // Ensure directory exists
              if (!existsSync(dir)) {
                await mkdirSync(dir, { recursive: true });
              }

              // Generate a unique handle using a counter instead of filename
              const handleId =
                Date.now().toString() + Math.random().toString(36).substr(2, 9);
              const handle = Buffer.from(handleId, "utf8");
              const stream = createWriteStream(fullPath);

              // Add error handling for the stream
              stream.on("error", (error) => {
                console.log(`❌ Stream error for ${filename}:`, error.message);
              });

              stream.on("finish", () => {
                console.log(`✅ Stream finished writing: ${filename}`);
              });

              const handleKey = bufferToString(handle);
              openFiles.set(handleKey, {
                filename: filename,
                stream: stream,
                bytesWritten: 0,
                fullPath: fullPath,
                handleId: handleId,
                originalHandle: handle,
              });

              console.log(
                `✅ File opened: ${filename} (handle: ${handle.toString(
                  "hex"
                )})`
              );
              console.log(`📁 Full path: ${fullPath}`);
              console.log(
                `🔑 Handle type: ${typeof handle}, Buffer: ${Buffer.isBuffer(
                  handle
                )}`
              );
              sftp.handle(reqid, handle);
            } catch (error) {
              console.log(`❌ Error opening file ${filename}:`, error);
              sftp.status(reqid, 2); // SSH_FX_NO_SUCH_FILE
            }
          });

          sftp.on("WRITE", async (reqid, handle, offset, data) => {
            console.log(
              `📝 WRITE request - Handle: ${handle.toString(
                "hex"
              )}, Offset: ${offset}, Data length: ${data.length}`
            );
            console.log(`📝 Available handles:`, Array.from(openFiles.keys()));

            const handleKey = bufferToString(handle);
            const fileInfo = openFiles.get(handleKey);
            if (!fileInfo) {
              console.log(
                `❌ Write to unknown handle: ${handle.toString("hex")}`
              );
              console.log(
                `❌ Handle type: ${typeof handle}, Buffer: ${Buffer.isBuffer(
                  handle
                )}`
              );
              console.log(`❌ Handle key: ${handleKey}`);
              console.log(
                `❌ Available keys: ${Array.from(openFiles.keys()).join(", ")}`
              );
              sftp.status(reqid, 9); // SSH_FX_BAD_MESSAGE
              return;
            }

            const bufferLength = data.length;
            fileInfo.bytesWritten += bufferLength;

            // Enhanced logging for PDF files and buffer analysis
            const isPDF = fileInfo.filename.toLowerCase().endsWith(".pdf");
            const fileType = isPDF ? "📄 PDF" : "📁 FILE";

            console.log(
              `${fileType} WRITE: ${fileInfo.filename} - Buffer length: ${bufferLength} bytes (Total: ${fileInfo.bytesWritten} bytes)`
            );

            // Log buffer details for PDF files
            if (isPDF) {
              console.log(`📊 PDF Buffer Analysis:`);
              console.log(`   - Chunk size: ${bufferLength} bytes`);
              console.log(`   - Offset: ${offset}`);
              console.log(
                `   - Total received: ${fileInfo.bytesWritten} bytes`
              );
              console.log(
                `   - Buffer preview: ${data.slice(0, 20).toString("hex")}...`
              );

              // Check for PDF header in first chunk
              if (offset === 0 && data.length >= 4) {
                const header = data.slice(0, 4).toString();
                if (header === "%PDF") {
                  console.log(`✅ Valid PDF header detected: ${header}`);
                } else {
                  console.log(`⚠️  Unexpected header: ${header}`);
                }
              }
            }

            try {
              // Write data synchronously to ensure it's written immediately
              const writeSuccess = fileInfo.stream.write(data);
              if (!writeSuccess) {
                // If write buffer is full, wait for drain event
                await new Promise((resolve) => {
                  fileInfo.stream.once("drain", resolve);
                });
              }
              sftp.status(reqid, 0); // SSH_FX_OK
            } catch (error) {
              console.log(
                `❌ Error writing to ${fileInfo.filename}:`,
                error.message
              );
              sftp.status(reqid, 4); // SSH_FX_FAILURE
            }
          });

          sftp.on("CLOSE", async (reqid, handle) => {
            const handleKey = bufferToString(handle);
            const fileInfo = openFiles.get(handleKey);
            if (!fileInfo) {
              console.log(`❌ Close unknown handle: ${handle.toString("hex")}`);
              console.log(`❌ Handle key: ${handleKey}`);
              console.log(
                `❌ Available keys: ${Array.from(openFiles.keys()).join(", ")}`
              );
              sftp.status(reqid, 9); // SSH_FX_BAD_MESSAGE
              return;
            }

            const isPDF = fileInfo.filename.toLowerCase().endsWith(".pdf");
            const fileType = isPDF ? "📄 PDF" : "📁 FILE";

            console.log(
              `${fileType} CLOSE: ${fileInfo.filename} - Total bytes written: ${fileInfo.bytesWritten}`
            );

            // Enhanced summary for PDF files
            if (isPDF) {
              console.log(`📊 PDF Upload Summary:`);
              console.log(`   - File: ${fileInfo.filename}`);
              console.log(`   - Total size: ${fileInfo.bytesWritten} bytes`);
              console.log(
                `   - Size (KB): ${(fileInfo.bytesWritten / 1024).toFixed(
                  2
                )} KB`
              );
              console.log(
                `   - Size (MB): ${(
                  fileInfo.bytesWritten /
                  (1024 * 1024)
                ).toFixed(2)} MB`
              );
              console.log(
                `   - Saved to: ${join(UPLOADS_DIR, fileInfo.filename)}`
              );
            }

            try {
              // Ensure all data is written before closing
              await new Promise((resolve, reject) => {
                fileInfo.stream.end((error) => {
                  if (error) reject(error);
                  else resolve();
                });
              });
              openFiles.delete(handleKey);
              sftp.status(reqid, 0); // SSH_FX_OK
            } catch (error) {
              console.log(
                `❌ Error closing ${fileInfo.filename}:`,
                error.message
              );
              sftp.status(reqid, 4); // SSH_FX_FAILURE
            }
          });

          sftp.on("READ", async (reqid, handle, offset, length) => {
            const handleKey = bufferToString(handle);
            const fileInfo = openFiles.get(handleKey);
            if (!fileInfo) {
              console.log(
                `❌ Read from unknown handle: ${handle.toString("hex")}`
              );
              console.log(`❌ Handle key: ${handleKey}`);
              console.log(
                `❌ Available keys: ${Array.from(openFiles.keys()).join(", ")}`
              );
              sftp.status(reqid, 9); // SSH_FX_BAD_MESSAGE
              return;
            }

            console.log(
              `📖 READ: ${fileInfo.filename} - Requested ${length} bytes from offset ${offset}`
            );
            // For this test server, we'll just return empty data
            sftp.data(reqid, Buffer.alloc(0));
          });

          sftp.on("READDIR", async (reqid, handle) => {
            console.log(`📂 READDIR request`);
            try {
              const files = [];
              sftp.name(reqid, files);
            } catch (error) {
              console.log(`❌ Error reading directory:`, error.message);
              sftp.status(reqid, 4); // SSH_FX_FAILURE
            }
          });

          sftp.on("STAT", async (reqid, path) => {
            console.log(`📊 STAT request: ${path}`);
            const fullPath = join(UPLOADS_DIR, path);

            try {
              if (existsSync(fullPath)) {
                const stats = statSync(fullPath);
                sftp.attrs(reqid, {
                  size: stats.size,
                  uid: stats.uid,
                  gid: stats.gid,
                  mode: stats.mode,
                  atime: Math.floor(stats.atime.getTime() / 1000),
                  mtime: Math.floor(stats.mtime.getTime() / 1000),
                });
              } else {
                sftp.status(reqid, 2); // SSH_FX_NO_SUCH_FILE
              }
            } catch (error) {
              console.log(`❌ Error getting file stats:`, error.message);
              sftp.status(reqid, 4); // SSH_FX_FAILURE
            }
          });

          sftp.on("MKDIR", async (reqid, path, attrs) => {
            console.log(`📁 MKDIR request: ${path}`);
            const fullPath = join(UPLOADS_DIR, path);

            try {
              await mkdirSync(fullPath, { recursive: true });
              console.log(`✅ Directory created: ${path}`);
              sftp.status(reqid, 0); // SSH_FX_OK
            } catch (error) {
              console.log(
                `❌ Error creating directory ${path}:`,
                error.message
              );
              sftp.status(reqid, 4); // SSH_FX_FAILURE
            }
          });

          // Handle other SFTP operations
          sftp.on("REALPATH", async (reqid, path) => {
            console.log(`🔗 REALPATH request: ${path}`);
            sftp.name(reqid, [{ filename: path, longname: path, attrs: {} }]);
          });

          sftp.on("OPENDIR", async (reqid, path) => {
            console.log(`📂 OPENDIR request: ${path}`);
            const handle = Buffer.from(path, "utf8");
            sftp.handle(reqid, handle);
          });

          sftp.on("RMDIR", async (reqid, path) => {
            console.log(`🗑️ RMDIR request: ${path}`);
            sftp.status(reqid, 0); // SSH_FX_OK
          });

          sftp.on("REMOVE", async (reqid, path) => {
            console.log(`🗑️ REMOVE request: ${path}`);
            sftp.status(reqid, 0); // SSH_FX_OK
          });

          sftp.on("RENAME", async (reqid, oldPath, newPath) => {
            console.log(`📝 RENAME request: ${oldPath} -> ${newPath}`);
            sftp.status(reqid, 0); // SSH_FX_OK
          });

          sftp.on("SETSTAT", async (reqid, path, attrs) => {
            console.log(`⚙️ SETSTAT request: ${path}`);
            sftp.status(reqid, 0); // SSH_FX_OK
          });

          // ssh2's createWriteStream chmods the handle right after OPEN and
          // waits for the reply before writing.
          sftp.on("FSETSTAT", async (reqid, handle, attrs) => {
            console.log(`⚙️ FSETSTAT request`);
            sftp.status(reqid, 0); // SSH_FX_OK
          });

          sftp.on("FSYNC", async (reqid, handle) => {
            console.log(`💾 FSYNC request`);
            sftp.status(reqid, 0); // SSH_FX_OK
          });
        });
      });
    });

    client.on("end", async () => {
      console.log(`🔌 Client disconnected: ${client.username}`);
    });

    client.on("error", async (err) => {
      console.log(`❌ Client error:`, err.message);
    });
  }
);

server.on("error", async (err) => {
  console.log(`❌ Server error:`, err.message);
  process.exit(1);
});

server.listen(PORT, "0.0.0.0", async () => {
  console.log(`🎉 SFTP server listening on port ${PORT}`);
  console.log("Press Ctrl+C to stop the server");
});

// Graceful shutdown
process.on("SIGINT", async () => {
  console.log("\n🛑 Shutting down SFTP server...");
  await new Promise((resolve) => {
    server.close(() => {
      console.log("✅ Server stopped");
      resolve();
    });
  });
  process.exit(0);
});
