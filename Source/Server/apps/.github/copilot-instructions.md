<!-- Copilot instructions tailored to the MacPatch Server apps workspace -->
# Copilot instructions — MacPatch Server (api & console)

Purpose: make PR-sized, safe, and idiomatic changes to the Flask-based `api` and `console` apps.

- **Big picture**: There are two Flask applications under `apps/`:
  - `apps/api` (package `mpapi`) is the machine-facing REST API. Entrypoint: api/app.py -> `mpapi.app:create_app()`.
  - `apps/console` (package `mpconsole`) is the admin web console. Entrypoint: console/app.py -> `mpconsole.app:create_app()`.
  Both use an application-factory pattern, register many blueprints (see `mpapi/app.py` and `mpconsole/app.py`), and load configuration from environment-dotfiles (`.mpglobal`, `.mpapi`, `.mpconsole`).

- **Config & env**:
  - Config objects live in `mpapi/config.py` and `mpconsole/config.py`. They load `.mpglobal` plus a per-app dotenv file in the apps directory.
  - Important config keys: `SITECONFIG_FILE` (site JSON), DB connection (`DB_*`), `URL_PREFIX` (API prefix `/api/v1`), `ALLOW_CONTENT_DOWNLOAD`, `ENABLE_INTUNE`, `USE_AWS_S3`.
  - When running locally mimic production by creating `.mpglobal` and `.mpapi`/`.mpconsole` files or export env vars used in those modules.

- **How apps are run**:
  - Production uses Gunicorn via `runapp.sh` which activates a virtualenv and calls `gunicorn --config gunicorn_config.py --chdir <app> "app:create_app()"`.
  - Gunicorn configs are `apps/api/gunicorn_config.py` and `apps/console/gunicorn_config.py`.

- **Dataflow & integrations**:
  - DB: SQLAlchemy (`mpapi/extensions.py` & `mpconsole/extensions`) + Flask-Migrate (`migrate.init_app`). DB URI is built from env vars in the config files.
  - Caching/sessions: `flask_caching` and Redis sessions in `mpconsole` (`SESSION_REDIS` in `mpconsole/config.py`).
  - AWS S3: wrapped by `mpapi/mpaws.py` and enabled via `USE_AWS_S3`.
  - Auth: `mpconsole` uses MSAL/Redis for auth flows; `mpapi` has token/auth blueprints. Local auth is behind `LOCAL_AUTH_ALLOWED`.

- **API patterns and conventions**:
  - Blueprints are organized by feature under `mpapi/` and `mpconsole/` and registered centrally in the `create_app()` factory.
  - API versioning: multiple blueprint versions exist (v1, v2, v3, v4). New endpoints should register under the correct version folder and URL prefix. Examples: `mpapi/agent`, `mpapi/agent_2`, `mpapi/agent_3`.
  - Agent compatibility: `mpapi/app.py` enforces a `BEFORE_REQUEST` bypass list and a min-agent-version check using an `HTTP_X_AGENT_VER` header. If you change agent protocol, update that check and the `MIN_AGENT_VER` config.

- **Logging & errors**:
  - Logging is configured in each app via `setup_logging()` (see `mpapi/app.py` and `mpconsole/app.py`). New modules should use `app.logger` or `mplogger` utilities where present.

- **Database models**:
  - All models are in `mpapi/model.py` and use a `CommonBase` pattern with `.asDict()` helpers used by many service responses—preserve these JSON-friendly semantics when adding fields.

- **Patterns to follow**:
  - Use the app factory (`create_app`) and `register_extensions()`/`register_blueprints()` pattern when adding features.
  - Put request-level checks in `before_request` or the blueprint-level before_request as appropriate (match existing `only_supported_agents` logic in `mpapi`).
  - When adding config flags, define defaults in the appropriate `config.py` and load them via the dotenv files.

- **Local developer workflow (discoverable from repo)**:
  - To run the apps the repository expects a virtualenv layout like `/opt/MacPatch/Server/env/<app>`. The `runapp.sh` scripts demonstrate how Gunicorn is invoked.
  - To iterate quickly in development, you can import the factory and run with Flask's dev server (example):
    ```py
    # quick dev run (ensure env vars loaded)
    from mpapi.app import create_app
    app = create_app()
    app.run(host='127.0.0.1', port=3601, debug=True)
    ```

- **What I couldn't find**:
  - There are no repository-wide unit tests or a test runner configuration present. If you add tests, document test commands in this file.

- **When opening PRs**:
  - Keep changes limited to a single concern (new route, model change, or config flag).
  - If touching DB models, include a migration (`flask db migrate`) and describe any required manual steps to run migrations in the PR.

If anything here is unclear or you'd like me to expand specific sections (deployment, migrations, or auth flows), tell me which part and I'll iterate.
