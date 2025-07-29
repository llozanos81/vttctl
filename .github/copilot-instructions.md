# Copilot Instructions for vttctl (FoundryVTT Docker Orchestration)

# General Guidelines
- Write clear, concise, and well-documented code.
- Follow existing code style and conventions.
- Ensure all new features are covered by tests.
- All variables and functions should have descriptive names in English.
- Use comments to explain complex logic or decisions in English.

# AI Instructions for chat editing text model
- When generating or modifying code, ensure it adheres to the project's conventions and patterns.
- Focus on clarity and maintainability.
- When adding new features, consider how they integrate with existing workflows.
- Think, Analyze, Plan, Implement, Test, Document each change.
- Ask clarifying questions if requirements are ambiguous or if additional context is needed.
- Check or validate language, syntax, and logic before finalizing changes.

## Project Overview
- This project manages FoundryVTT deployments using Docker, supporting multiple versions and backup/restore workflows.
- Main entrypoint: `vttctl.sh` (Bash script, root of repo). All major operations (build, start, stop, backup, restore, etc.) are invoked via this script.
- Docker images are versioned per FoundryVTT release (see `FoundryVTT/foundryvtt.json` for supported versions and base images).
- Docker Compose files: `docker/docker-compose.yml` (production), `docker/docker-compose-dev.yml` (development/testing).
- User data and backups are stored in Docker volumes and the `backups/FoundryVTT/` directory.

## Key Workflows
- **Setup:**
  1. Run `./vttctl.sh validate` to check dependencies and generate `.env` from `dotenv.example`.
  2. Download FoundryVTT zip using a timed URL: `./vttctl.sh download "TIMED_URL"`.
  3. Extract and build images: `./vttctl.sh build` (select version interactively).
  4. Set default version: `./vttctl.sh default`.
  5. Start services: `./vttctl.sh start`.
- **Backups:** `./vttctl.sh backup` creates a backup tarball and updates metadata.
- **Restore:** `./vttctl.sh restore` interactively restores from available backups.
- **Cleaning:** `./vttctl.sh clean`/`cleanup` removes containers, images, and optionally user data.

## Project Conventions & Patterns
- All versioned FoundryVTT binaries are extracted to `FoundryVTT/<version>/`.
- Dockerfiles are version-specific: `FoundryVTT/Dockerfile.<major_version>`.
- The main Dockerfile is symlinked/copied to `FoundryVTT/Dockerfile` before build.
- Environment variables are loaded from `.env` (see `dotenv.example` for required keys).
- User and group IDs for containers are always `3000:3000` (do not change).
- All Docker Compose commands are wrapped by `vttctl.sh` for correct env setup.
- Backups are stored in `backups/FoundryVTT/` and indexed in `metadata.json`.
- The script expects to be run as a non-root user in the `docker` group.

## Integration Points
- FoundryVTT app runs in the `app` container, Nginx in `web`, and (optionally) ddb-proxy in `ddb`.
- Nginx config: `docker/nginx/foundry.conf`.
- Entrypoint for app container: `FoundryVTT/docker-entrypoint.sh` (sets up env, runs pm2, etc.).
- Compose networks: `frontend` (external), `backend` (internal).

## Examples
- Build a new version: `./vttctl.sh build` (choose version interactively)
- Restore backup: `./vttctl.sh restore` (choose backup interactively)
- Set default version: `./vttctl.sh default`

## Special Notes
- Do not edit Docker Compose files or Dockerfiles directly for version changes; use the provided scripts.
- Always use the `vttctl.sh` wrapper for all operations to ensure correct environment and permissions.
- For new FoundryVTT versions, update `FoundryVTT/foundryvtt.json` and add a matching Dockerfile if needed.

---
For more, see `README.md` and comments in `vttctl.sh`.
