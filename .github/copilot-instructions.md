# GitHub Copilot Instructions for legendaryrealms.com.mx (vttctl FoundryVTT Docker Orchestration)
**Copilot must always follow these rules when working in this repository.**

## General Principles
- Write clear, maintainable, and secure code.
- Prefer explicit over implicit behavior.
- Use descriptive variable and function names in English.
- Add comments for non-trivial logic and document assumptions.
- Avoid unused code or features not requested.
- Validate language, syntax, and logic before finalizing changes.
- Ask clarifying questions if requirements are ambiguous.
- Prefer the most secure and maintainable solution if multiple exist.

## Project-Specific Guidelines
- Main entrypoint: `vttctl.sh` (Bash script, root of repo). All major operations are invoked via this script.
- Docker images are versioned per FoundryVTT release (`FoundryVTT/foundryvtt.json`).
- Compose files: `docker/docker-compose.yml` (production), `docker/docker-compose-dev.yml` (development/testing).
- User data and backups: Docker volumes and `backups/FoundryVTT/`.
- All FoundryVTT binaries: `FoundryVTT/<version>/`.
- Dockerfiles: `FoundryVTT/Dockerfile.<major_version>`, symlinked/copied to `FoundryVTT/Dockerfile` before build.
- Environment variables: `.env` (see `dotenv.example`).
- Container user/group IDs: always `3000:3000`.
- All Docker Compose commands must be wrapped by `vttctl.sh`.
- Backups: `backups/FoundryVTT/`, indexed in `metadata.json`.
- Run scripts as non-root user in the `docker` group.
- Do not edit Docker Compose files or Dockerfiles directly for version changes; use scripts.
- For new FoundryVTT versions, update `foundryvtt.json` and add a matching Dockerfile.

## Bash Guidelines
- Prefer POSIX compliance unless Bash-only features are required.
- Start scripts with:
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  IFS=$'\n\t'
  ```
- Quote all variable expansions: `"${VAR}"`
- Never hardcode paths; use variables or parameters.
- Validate all user inputs before using them in commands.
- Avoid `eval` and unsafe command substitution.
- Use safe flags for file operations:
  ```bash
  rm -rf -- "${TARGET_DIR}"
  ```
- Use `shellcheck`-compliant syntax and suggest fixes when possible.
- Prefer clear structure in loops and conditions.
- Include a short usage block at the top of scripts.

## Python Guidelines
- Follow PEP 8 (style) and PEP 257 (docstrings).
- Use type hints for all functions.
- Default to Python 3.11+ syntax.
- Use `pathlib` over `os.path` where possible.
- Wrap file/network operations in try/except with specific exceptions.
- Use f-strings for formatting.
- Prefer list/dict comprehensions for clarity.
- Make functions pure and testable.
- Avoid bare `except:` clauses.
- Use `with` statements for resource management.
- Avoid monolithic functions — prefer smaller, focused functions.

## Documentation & Comments
- Add docstrings to all public functions/classes.
- Explain complex logic, assumptions, and integration points.
- Note external patterns or sources when relevant.

## Security & Safety
- Never expose secrets or credentials.
- Sanitize all external inputs.
- Avoid destructive commands unless explicitly requested.
- Validate SSL and handle errors for network requests.

## Testing & Validation
- For Python, generate unit tests using `pytest` style when requested.
- For Bash, provide simple test cases or usage examples.
- Ensure code runs without syntax errors before suggesting it.

## Prompt-Specific Behavior
- If unclear, ask clarifying questions in comments instead of making unsafe assumptions.

---


## 2. Bash Guidelines
- **POSIX compliance first**, unless explicitly told to use Bash-only features.
- Always start scripts with:
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  IFS=$'\n\t'
  ```
- Quote all variable expansions: "${VAR}"
- Never hardcode paths; use variables or parameters.
- Validate all user inputs before using them in commands.
- Avoid `eval` and unsafe command substitution.
- When deleting or modifying files, always use safe flags:
  ```bash
  rm -rf -- "${TARGET_DIR}"
  ```
- Use `shellcheck`-compliant syntax and suggest fixes when possible.
- If loops or conditions can be simplified, prefer clear structure over golfing.

---

## 3. Python Guidelines
- Follow **PEP 8** for style and **PEP 257** for docstrings.
- Use **type hints** for all functions:
  ```python
  def process_data(data: list[str]) -> list[str]:
      """Process input data and return a cleaned list."""
  ```
- Default to **Python 3.11+** syntax.
- Always use `pathlib` instead of `os.path` where possible.
- Wrap file and network operations in `try/except` with specific exceptions.
- Use f-strings for string formatting.
- Prefer list/dict comprehensions over manual loops when it improves clarity.
- Make functions pure and testable where possible.
- Avoid bare `except:` clauses — catch specific errors.
- Use `with` statements for resource management.

---

## 4. Documentation & Comments
- Add **docstrings** to all public functions/classes.
- For Bash, include a short usage block at the top of the script.
- Explain assumptions and non-obvious logic.
- If Copilot generates code from an external pattern, note its purpose.

---

## 5. Security & Safety
- Never expose secrets or credentials in code.
- Sanitize all external inputs before use.
- Do not generate commands that can cause destructive changes unless explicitly requested.
- For network requests, validate SSL and handle errors.

---

## 6. Testing & Validation
- For Python, generate unit tests using `pytest` style when requested.
- For Bash, provide simple test cases or usage examples.
- Ensure generated code runs without syntax errors before suggesting it.

---

## 7. Prompt-Specific Behavior
When unclear, **ask clarifying questions in comments** instead of making unsafe assumptions.  
If multiple solutions exist, generate the **most secure and maintainable** one.
Analyze, Think, reason, and clarify requirements before implementing solutions.


---

**Copilot must always follow these rules when working in this repository.**
