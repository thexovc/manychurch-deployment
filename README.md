# ManyChurch Deployment & Infrastructure

This repository contains the infrastructure configurations, deployment scripts, orchestration configurations, and CI/CD pipelines for the **ManyChurch** microservices platform.

## Architecture Overview

ManyChurch is structured as a collection of microservices communicating with each other and backed by standard storage and messaging systems:

*   **Proxy (Nginx)**: Edge reverse proxy routing external requests.
*   **Gateway Service**: Entry point for clients, routing to individual internal services.
*   **Auth Service**: Handles user authentication, token generation (JWT), and security.
*   **Church Service**: Microservice managing church-specific records.
*   **Member Service**: Microservice managing church members and directory.
*   **Notification Service**: Handles system notifications using RabbitMQ as the message broker.
*   **Additional Microservices**: Course, Giving, Wallet, Support, and Admin services.
*   **Database (PostgreSQL)**: Core relational database.
*   **Cache (Redis)**: Performance caching and session management.
*   **Broker (RabbitMQ)**: Message queue for asynchronous event processing.

---

## Directory Structure

```
├── .github/
│   └── workflows/
│       ├── deploy-dev.yml       # Dev environment deployment workflow
│       └── deploy-prod.yml      # Prod environment deployment workflow
├── nginx/
│   ├── Dockerfile               # Custom Nginx build file
│   └── nginx.conf               # Nginx reverse proxy configuration
├── terraform/
│   ├── environments/
│   │   ├── dev/                 # Dev environment provisioning
│   │   └── prod/                # Prod environment provisioning
│   └── modules/
│       └── ecs_ec2/             # Reusable module for deploying ECS on EC2
├── docker-compose.yml           # Local multi-container development configuration
├── .gitignore                   # Version control ignore rules
└── README.md                    # Project documentation (this file)
```

---

## Local Development

You can run the entire ManyChurch stack locally using Docker Compose:

1.  **Configure Environment Variables**:
    Create a `.env` file in the root directory (based on your configuration) containing:
    *   `PROXY_IMAGE`, `GATEWAY_IMAGE`, `AUTH_IMAGE`, `CHURCH_IMAGE`, `MEMBER_IMAGE`, `NOTIFICATION_IMAGE` (Docker image URIs)
    *   `DB_PASSWORD` (Postgres password)
    *   `REDIS_PASSWORD` (Redis authentication secret)
    *   `RABBITMQ_PASSWORD` (RabbitMQ password)
    *   `JWT_SECRET` (JSON Web Token signing key)
    *   `ENVIRONMENT` (e.g., `development`)

2.  **Start Services**:
    ```bash
    docker compose up -d
    ```

3.  **Stop Services**:
    ```bash
    docker compose down
    ```

---

## Deployment (AWS ECS on EC2)

Deployment is managed using **Terraform** to provision a single ECS cluster running on an EC2 instance (e.g., `t3.small` / `t3.medium`).

### Environments
*   **Dev**: Configured in [terraform/environments/dev/](file:///Users/danielosariemen/Documents/Daniel-jobs/ManyChurch/manychurch-deployment/terraform/environments/dev)
*   **Prod**: Configured in [terraform/environments/prod/](file:///Users/danielosariemen/Documents/Daniel-jobs/ManyChurch/manychurch-deployment/terraform/environments/prod)

### Automated Deployments via GitHub Actions
GitHub Actions automatically trigger deployment on pushes to target branches:
*   Pushing to `dev` triggers the [deploy-dev.yml](file:///Users/danielosariemen/Documents/Daniel-jobs/ManyChurch/manychurch-deployment/.github/workflows/deploy-dev.yml) workflow.
*   Pushing to `prod` triggers the [deploy-prod.yml](file:///Users/danielosariemen/Documents/Daniel-jobs/ManyChurch/manychurch-deployment/.github/workflows/deploy-prod.yml) workflow.

The CI/CD pipeline performs the following steps:
1.  Logs in to Amazon ECR.
2.  Builds and pushes the custom Nginx Proxy image.
3.  Initializes and applies Terraform plans to update the ECS task definitions and deployment.
