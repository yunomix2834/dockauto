Project name: dockauto
Purpose: This project was built to auto build container in dev environment
State machine: INIT -> VALIDATE -> HASH -> BUILD -> SCAN -> INFRA -> TEST -> CLEANUP
Steps in flows:
- Step 0: We need some way that user can download this project's lib and user can cli to generate a "Project's Template" to define configurations. 
  - This template was designed similarly Docker Compose yaml file

```yml
version: "3.9"

# ==== DOCKAUTO META (ROOT) ====
x-dockauto:
  project:
    name: my_app
    main_service: app           
    language: node              
    language_version: "22"

  build:
    lockfiles:
      - package-lock.json
    # nếu muốn ép dùng template thay vì Dockerfile có sẵn:
    # dockerfile_template: node

  tests:
    enabled: true
    default_suites: ["unit"]
    suites:
      unit:
        cmd: "npm test"
        requires_infra: []      
      integration:
        cmd: "npm run test:integration"
        requires_infra: ["db", "redis"]

  security:
    scan:
      enabled: true
      tool: trivy
      fail_on: ["CRITICAL","HIGH"]
      output: "reports/security"
    sbom:
      enabled: true
      tool: syft
      format: "spdx-json"
      output: "reports/sbom"

  profiles:
    dev:
      description: "Local development"
    ci:
      description: "CI pipeline build + full tests"

# ==== COMMON ANCHORS ====
x-common-environment: &default-env
  APP_ENV: development
  TZ: Asia/Ho_Chi_Minh

x-common-labels: &default-labels
  maintainer: "your_name"
  project: "my_app"

# ==== SERVICES ====
services:
  app:
    container_name: myapp-app

    build:
      context: .
      dockerfile: Dockerfile
      args:
        NODE_ENV: development

    image: myapp:latest
    restart: unless-stopped

    command: ["npm", "run", "start"]

    ports:
      - "8080:3000"

    environment:
      <<: *default-env
      DB_HOST: db
      DB_PORT: 5432
      DB_USER: myapp
      DB_PASSWORD: secret
      DB_NAME: myapp_db
      REDIS_HOST: redis
      REDIS_PORT: 6379

    env_file:
      - .env

    volumes:
      - ./:/usr/src/app
      - app_logs:/var/log/myapp

    depends_on:
      - db
      - redis

    networks:
      - backend
      - frontend

    labels:
      <<: *default-labels
      component: "backend"

    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s

    # Metadata cho dockauto.sh riêng cho service app
    x-dockauto:
      role: app              # đánh dấu đây là service chính
      test_target: true      # service này dùng để chạy test (docker run ...)
      optimize_build: true   # sau này dùng cho step 4.5

  db:
    image: postgres:16
    container_name: myapp-db
    environment:
      POSTGRES_DB: myapp_db
      POSTGRES_USER: myapp
      POSTGRES_PASSWORD: secret
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myapp -d myapp_db"]
      interval: 10s
      timeout: 5s
      retries: 5
    x-dockauto:
      role: infra
      type: postgres

  redis:
    image: redis:7
    container_name: myapp-redis
    volumes:
      - redis_data:/data
    networks:
      - backend
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    x-dockauto:
      role: infra
      type: redis

# ====== VOLUMES ======
volumes:
  db_data:
  redis_data:
  app_logs:
  nginx_logs:

# ====== NETWORKS =====
networks:
  backend:
    driver: bridge
  frontend:
    driver: bridge
```

    + Install / Update: 
        Script:
        Binary versioning: 
            dockauto --version
            dockauto self-update (FUTURE)
    + Template: 
        dockauto init --lang node
        dockauto init --lang python
        dockauto init --from-compose docker-compose.yml (import from compose to generate dockauto.yml)
    + Doc in template
        comment -> user easily to edit

- Step 1: CLI and parse arugment: 
  - This step want to know what user thinks, retrieve command from "dockauto.yml" and execute.
  - This lib expected be:
    dockauto/
        bin/dockauto
        lib/cli.sh
            + GLOBAL:
                + --profile 
                + --verbose: log debug
                + --quiet
                + --config
            + FLAG:  
                + yq mean parse yml. jq mean parse yml -> json
                + BUILD
                  + --infra (Check in step 2)
                  + --skip-test (Check in step 2) -> if false then will not test
                  + --ignore-test-failure -> warning if does not pass the test
                  + --no-scan (vulnerability and Check & install in step 2)
                  + --test -> unit or integration
                + UP
                  + --keep-infra -> default (false)
            + EXTENDS:
                + -p 8080: to check port has been used or not
                + -n <network_name>: to check network in docker has been used or not

        lib/config.sh
        lib/validate.sh
        lib/build.sh
        lib/infra.sh
        lib/test.sh
        lib/scan.sh
        lib/utils.sh: log_debug, log_info, log_warn, log_error with color.
        ...
  - Set "set -euo pipefail", "--" to more safely
  - CLI: subcommand:
    + dockauto template / init
    + dockauto build
    + dockauto test
    + dockauto up/down

- Step 2: Read and Validate dockauto.yml
  - Goals: get all detail information in yml: 
    + language, context, version, dependencies, test, db/broker
  - Check
    + dockauto.yml: exist
    + validate supported lang
    + check language version, context, check and update template
    + check essentials lib: node -> install nodejs, trivy -> install, SBOM -> install...
      + Print suggestion install tools (But do not install directly)
    + check test suite if --skip-test is true
    + check infra if rqr-infra is true
    + use jq to parse yml to json report

- Step 3: Calculate build hash
  - Goals: Decide build or reuse cache
  - Create fingerprint
    + Merge dockauto.yml
    + Version template
    + ...
    + CONFIG_HASH = dockerauto.yml + template version
    + SOURCE_HASH = sourcecode + lockfiles
    + BUILD_HASH = sha256 (CONFIG_HASH + SOURCE_HASH)
  - Calculate hash -> print
  - Check cache (if exist)
  - Ignore unnecessary file
    + .dockautoignore: node_modules, tmp, log, .git
  - Concurrent safety: 
    + When many processes concurrently build, avoid break .dockauto/cache.json -> Use file lock (flock) or atomic write
      + Write in temp file -> mv

- Step 4: Generate Dockerfile from Template
  - If Dockerfile was designated  -> do not generate, use that file to build
  - From language
  - Prepare environment
  - Versioning template
    + # dockauto-template-version: 1
    + Write this version in fingerprint -> when up template, hash is diff -> rebuild

- Step 4.5: Automate optimize dockerfile to prepare build in step 3
  (Cái này khả năng chưa làm luôn vì sẽ thêm các option ở cli ứng với build theo image gì để phù hợp với ngữ cảnh build)
  + --optimize-cache (multi-stage, layer cache)
  + --optimize-install (install deps before copy source)

- Step 5: Build image (Docker)
  - Export log + report: hash → tag → id → digest → created_at -> Format log to human readable
  - jq to update cache file
  - (Sau này) Support buildx / multi-arch

- Step 6: Scan image with Trivy, SBOM
    ```yml
    security:
      scan:
        enabled: true
        tool: trivy
        fail_on: ["CRITICAL","HIGH"]
        output: "reports/security"
      sbom:
        enabled: true
        tool: syft
        format: "spdx-json"
        output: "reports/sbom"
    
    ```
  - Export report

- Step 7: Provision infra for test (Database, Broker)
  - Config db, broker service
  - Config network, port
    + Port conflict handling: 
      + if not assign any port -> random port -> docker inspect to retrieve port
  - Loop healthcheck
  - If --kep-infra = true -> test reuse -> healthcheck

- Step 8: Test
  - if --skip-test: skip this step, and log warning
  - --test = unit, integration -> test with suite 
    + test unit before integration. If unit fail -> do not provision infra (because unit do not dependence infra)
  - Ensure that have infra to test
  - If suite fail
    + default: file dockauto build
    + if flag --ignore-test-failure = true -> warning
  - Parallel test (FUTURE)
  - Loop write log, export log + report -> format report

- Step 9: Teardown infra
  - if --keep-inra = false -> remove and delete container infra, network
    + Naming conversion to avoid delete mistake: dockauto_test_<hash>_db
    + Avoid delete mistake container dev. Dev infra: dockauto_dev_db
  - trap if script Ctrl+C will clean.

!Notice:
- Pin version
- Comment Step -> Clean code