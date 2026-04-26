# backup-a Project Guidelines

This file outlines the core principles, design decisions, and testing methodologies for the `backup-a` containerized backup solution. As an AI assistant, strictly adhere to these guidelines when working on this project.

## Core Design Principles

1.  **Architecture**: `backup-a` is an Alpine-based container that utilizes `ofelia` for task scheduling and `rclone` for syncing to S3-compatible storage (e.g., Cloudflare R2, MinIO).
2.  **Multi-threaded Compression**: Backups are compressed using `pigz` for maximum efficiency. The number of threads (`PIGZ_THREADS`) is dynamically calculated at runtime (defaulting to 80% of available CPU cores, capped at 4) unless explicitly overridden via an environment variable.
3.  **Memory Management**: Rclone's upload buffer can be controlled via `RCLONE_BUFFER_SIZE` (default: 16M). Setting this to `0` or a small value helps prevent OOM on memory-constrained systems.
4.  **Strict Read-Only Enforcement**: To ensure absolute data safety, the entrypoint script rigorously checks all mounts under the `/backup/` directory. If any mount is found to be writable (`rw`), the container will immediately exit with a critical error. **Never bypass this check.**
5.  **Pre-flight Connectivity Check**: Before starting the scheduler (`entrypoint.sh`) and before each backup run (`backup.sh`), the container performs an `rclone rcat` ping test to ensure the target bucket is both reachable and writable. This "fail-fast" mechanism prevents unnecessary CPU usage if storage is unavailable.
6.  **Granular Archiving**: The backup script (`backup.sh`) iterates through each immediate subdirectory within `/backup/` and compresses them into individual archives (e.g., `dirname_YYYYMMDD_HHMMSS.tar.gz`).
7.  **Simplified Configuration**: Rclone configuration is generated dynamically from a flat list of environment variables (`TYPE`, `PROVIDER`, `ENDPOINT`, `ACCESS_KEY`, `SECRET_KEY`, `BUCKET`) to simplify deployment.
8.  **Automated Retention**: A retention policy (`RETENTION_DAYS`) is enforced via a dedicated `prune.sh` script, scheduled independently by `ofelia`.
9.  **Webhook Notifications**: Support for sending JSON payloads to a specified `WEBHOOK_URL` upon task completion (Success or Failure).
10. **Manual Management Utility**: A `manage.sh` script is symlinked to `/usr/local/bin/` as `list`, `check`, `backup`, `prune`, and `prune-auto` for easy execution via `docker exec`.
11. **Base Image**: The official published image for this project is `docker.io/ailing2416/backup-a:1.0`.

## Testing Methodology

When modifying the logic or adding features, follow these testing procedures using a remote VM (e.g., `backup-a` or `backup-server`):

### 1. Safety Mechanism Test (RW vs RO Mounts)
*   **RW Test**: Modify `docker-compose.yml` to remove the `:ro` flag from volume mounts. Start the container and verify via logs that it correctly identifies the rw mount, logs a critical error (`CRITICAL: Please use ':ro'`), and exits.
*   **RO Test**: Restore the `:ro` flags. Start the container and verify it successfully initializes and starts the `ofelia` scheduler.

### 2. Execution and Thread Calculation Test
*   Manually trigger the backup script within the running container: `docker-compose exec backup-a /backup.sh`
*   Verify the output logs show the correct calculation of `PIGZ_THREADS` based on the VM's available cores.

### 3. End-to-End Backup and Upload Test
*   Deploy a temporary S3-compatible server (like MinIO) on a test VM (e.g., `backup-server`).
*   Update the `docker-compose.yml` environment variables to point to the test MinIO instance.
*   Create dummy directories and files under the host paths mapped to `/backup/`.
*   Trigger the backup script.
*   Verify the logs indicate successful compression and upload.
*   Connect to the MinIO instance (e.g., using `mc ls`) to confirm the `.tar.gz` files were successfully uploaded to the correct bucket and subdirectory paths.

### 4. Retention Policy Test
*   To test retention, you may need to manually manipulate the modified dates of files in the test S3 bucket or temporarily set `RETENTION_DAYS` to a very low value (e.g., 1 day) and wait/simulate time passing to ensure old backups are pruned by the script.

## Development Mandates

*   **Do not introduce complex bash logic** where standard tools (`awk`, `jq`) suffice, but keep dependencies minimal (relying on Alpine's default packages where possible).
*   **Maintain verbose logging** in `backup.sh` for easy debugging of the cron jobs.
*   **Always use the designated published image** (`docker.io/ailing2416/backup-a:1.0`) as a reference point for the baseline working state.
