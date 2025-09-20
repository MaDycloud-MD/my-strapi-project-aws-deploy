# Strapi Project Documentation

### Project Overview

* **Name**: Strapi Headless CMS on AWS
* **Goal**: Deploy a production-ready Strapi instance on AWS using Terraform, containerize Strapi, use RDS(Postgres) for persistence, and secure credentials with Secrets Manager.
* **Stack**: Strapi (Node.js), Docker, ECR, ECS Fargate, RDS(Postgres), AWS Secrets Manager, CloudWatch, Terraform.

### High-level Architecture

1. Developer builds Strapi image locally (or CI) → pushes to **ECR**.
2. Terraform provisions a minimal infra in the **default VPC**: RDS (Postgres), ECS cluster & Fargate task, IAM roles, security group, CloudWatch log group.
3. ECS pulls image from ECR, injects secrets from **Secrets Manager**, and runs Strapi task.
4. Strapi connects to RDS over TLS (recommended) and serves the admin/API on port 1337.

### Key Files & Components

* `Dockerfile` — multi-stage, builds admin panel and installs production dependencies inside the container. Prefer `node:22-slim` to avoid Alpine musl vs glibc issues.
* `docker-compose.yml` — local development: Strapi + Postgres for testing.
* `infra/main.tf` — Terraform code to create DB, ECS, IAM roles, SG, and log group. Minimal variant uses default VPC for simplicity.
* `config/database.js` — Strapi DB config reading env vars (`DATABASE_HOST`, `DATABASE_SSL`, etc.).
* `config/plugins.js` — S3 upload provider (optional) for production file storage.

### Deployment Steps (summary)

1. Build & test locally with Docker Compose.
2. Build image for Fargate:

```bash
docker buildx build --platform linux/amd64 -t my-strapi:prod .
docker tag my-strapi:prod <ACCOUNT>.dkr.ecr.<region>.amazonaws.com/strapi:latest
docker push <ACCOUNT>.dkr.ecr.<region>.amazonaws.com/strapi:latest
```

3. Deploy infra with Terraform:

```bash
terraform init
tfplan
terraform apply -auto-approve
```

4. Check ECS task and CloudWatch logs (`/ecs/strapi`) for runtime output.

### Environment & Secrets

* Required env vars for Strapi:

  * `DATABASE_CLIENT`, `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`
  * `DATABASE_SSL` (true/false) and optionally `PGSSLMODE=require`
  * `JWT_SECRET`, `APP_KEYS`, `ADMIN_JWT_SECRET`, `API_TOKEN_SALT`
* Use **AWS Secrets Manager** to store and inject these values into ECS tasks via the `secrets` block in the task definition.

### Problems Faced & Solutions (detailed)

1. **Wrong COPY paths in Dockerfile**

   * Problem: `COPY --from=builder /my-strapi-project/build` failed because `WORKDIR` was `/app`.
   * Fix: Use consistent paths (`/opt/app` or `/app`) and copy the whole build folder from the builder stage.

2. **Missing `build/` folder confusion**

   * Problem: Strapi's `npm run build` compiles the admin panel; dev expectations differ from frontend frameworks.
   * Fix: Ensure `npm run build` runs in the builder stage and that the builder's app directory is copied to the runtime stage.

3. **Native binary mismatches (better-sqlite3, esbuild)**

   * Problem: Binaries compiled on macOS/ARM won't run on Linux Fargate (Exec format error / version mismatch).
   * Fix: Install build tools and compile native modules inside the builder image, or switch to `node:22-slim`. Use `npm rebuild esbuild` or `npm rebuild --build-from-source` in the container when necessary.

4. **esbuild / vite errors on Alpine**

   * Problem: esbuild binary mismatch caused admin build to fail.
   * Fix: Prefer Debian-slim base image or force rebuild of esbuild for linux/amd64.

5. **Image architecture mismatch**

   * Problem: Built image on M1/M2 defaults to ARM; Fargate expected x86\_64.
   * Fix: Build with `--platform linux/amd64` or use multi-platform buildx and push the correct image.

6. **DB connection issues (127.0.0.1, Host not found)**

   * Problem: Running container tried to connect to `127.0.0.1`.
   * Fix: Use Docker Compose service names (`postgres`) locally; use RDS endpoint in ECS.

7. **RDS VPC mismatch**

   * Problem: RDS and SG were in different VPCs.
   * Fix: Create `aws_db_subnet_group` with subnets from the same VPC or deploy everything in default VPC.

8. **ECS execution role missing**

   * Problem: Fargate requires an execution role to pull images.
   * Fix: Add `aws_iam_role` with `AmazonECSTaskExecutionRolePolicy` and set `execution_role_arn` in task definition.

9. **SSL / pg\_hba.conf errors**

   * Problem: `no pg_hba.conf entry` or `self-signed certificate` when connecting to RDS.
   * Fix: Configure `DATABASE_SSL=true` and `PGSSLMODE=require`, or add `DATABASE_SSL_REJECT_UNAUTHORIZED=false` for dev. For prod, include RDS CA certificate in image or trust it via system CA bundle.

10. **Missing Strapi JWT secrets**

    * Problem: Strapi requires `JWT_SECRET`/`APP_KEYS` in production.
    * Fix: Generate secure random secrets and inject via Secrets Manager.

### How I tested & validated

* Local: `docker-compose up --build`, test admin UI at `http://localhost:1337/admin`.
* CI: image build + push to ECR using `docker buildx` for platform targeting.
* AWS: `terraform apply`, then monitor CloudWatch logs `/ecs/strapi` to verify Strapi boots and connects to DB.

### Outcome & Next Steps

* A reproducible Terraform + Docker deployment pattern for Strapi on AWS Fargate with RDS.
* Next: add S3 uploads for media, enable HTTPS via ALB+ACM, and lock down SGs for production.

---

