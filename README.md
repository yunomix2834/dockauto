## Install

```bash
curl -fsSL https://raw.githubusercontent.com/yunomix2834/dockauto/main/install.sh | bash

## Quick start

```bash
dockauto init --lang node      # generate dockauto.yml
dockauto build                 # build image
dockauto test --infra          # run tests (with db/redis)
dockauto up --keep-infra       # start dev infra
