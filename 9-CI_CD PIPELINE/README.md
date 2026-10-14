# Basic CI/CD Pipeline Assignment

This repository is a standalone GitHub Actions CI/CD demonstration. It is separate from the Docker assignment.

## Pipeline stages

1. **Code push / pull request** — GitHub Actions starts on pushes and pull requests to `main` or `master`.
2. **Test** — pytest runs automated API tests.
3. **Dependency scan** — `pip-audit` checks Python dependencies for known vulnerabilities.
4. **Build** — Docker builds a versioned image tagged with the Git commit SHA.
5. **Image security scan** — Trivy checks OS and library packages for HIGH and CRITICAL vulnerabilities.
6. **Terraform validation** — Terraform checks formatting, initializes without a remote backend, and validates the sample configuration.
7. **Deployment** — the workflow simulates deployment after the checks pass. It does not deploy to AWS.

## Run locally

Python 3.12 and Docker are recommended.

```bash
python -m venv .venv
# Windows PowerShell:
.venv\\Scripts\\Activate.ps1
# macOS/Linux:
# source .venv/bin/activate

pip install -r requirements-dev.txt
pytest -v
docker build -t cicd-demo:local .
docker run --rm -p 8000:8000 cicd-demo:local
```

Open `http://localhost:8000/health` or `http://localhost:8000/docs`.

To validate Terraform locally, install Terraform and run:

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

## Deployment limitation

The deployment job is deliberately a simulation because no deployment account or target is configured. To make it real, configure a target environment, registry, credentials through GitHub Secrets or (preferably on AWS) GitHub OIDC, and a deployment command appropriate to the target.

## Rollback strategy

For a real deployment:

1. Build each release with an immutable image tag, preferably the Git commit SHA; do not rely only on `latest`.
2. Deploy to a staging environment first and run smoke/health checks.
3. For a rolling deployment, monitor error rate, latency, health checks, and application logs.
4. If checks fail, stop promotion and redeploy the previous known-good image tag.
5. For Kubernetes, use `kubectl rollout undo deployment/<name>` or `helm rollback <release> <revision>`.
6. For EC2, keep the previous application artifact/image available and switch the service back to the previous version; use an Auto Scaling / load-balancer strategy where appropriate.
7. Verify the rollback with health checks and retain logs and the failed release identifier for investigation.

Database changes need a separate backward-compatible migration plan; rolling back application code alone may not safely reverse a destructive schema change.

## Security notes

- The Trivy step fails on detected HIGH or CRITICAL vulnerabilities that are not marked as unfixed.
- The dependency audit can fail the pipeline if vulnerable packages are found; update dependencies and rerun.
- Pin third-party GitHub Actions to reviewed versions or commit SHAs for stricter supply-chain controls.
- Do not commit credentials, private keys, `.env` files, or AWS access keys.
