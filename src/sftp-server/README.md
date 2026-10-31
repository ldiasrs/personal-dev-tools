# SFTP Test Server

A local SFTP server for testing uploads. It logs every operation and buffer
length, with extra detail for PDFs (header check, chunk sizes, upload summary).
Uploaded files land in `src/sftp-server/uploads/`.

> Test server only: hardcoded credentials, no access control. Never expose it.

## Run

```bash
npm run sftp-server                  # listens on localhost:2222
npm run sftp-test                    # uploads a small generated PDF
npm run sftp-test -- ./some/file.pdf # uploads a file of your choice
sftp -P 2222 testuser@localhost      # password: testpass
```

On first run the server generates its own host key in `keys/` with
`ssh-keygen`. The key and `uploads/` are gitignored.

## Configuration

| Env var | Default |
|---|---|
| `SFTP_PORT` | `2222` (port 22 needs `sudo`) |
| `SFTP_USER` / `SFTP_PASS` | `testuser` / `testpass` |
| `SFTP_UPLOADS_DIR` | `src/sftp-server/uploads` |
| `SFTP_HOST_KEY` | `src/sftp-server/keys/host_key` |

The test client reads the same `SFTP_PORT`, `SFTP_USER` and `SFTP_PASS`.

## Notes

- `READ` returns empty data and `READDIR` an empty list: the server is built
  to receive files, not serve them.
- `REMOVE`, `RENAME`, `RMDIR` and `SETSTAT` are acknowledged but do nothing.
