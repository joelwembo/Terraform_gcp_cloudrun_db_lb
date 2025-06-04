# Terraform GCP Cloud Run, Cloud SQL, and Load Balancer Blueprint

This repository contains a Terraform configuration to provision a scalable application architecture on Google Cloud Platform (GCP), including:

-   A managed **Cloud SQL** instance (PostgreSQL or MySQL)
-   A serverless **Cloud Run** service (v2) to host a containerized application
-   A **Global External HTTP Load Balancer** with a static IP, routing traffic to Cloud Run via a Serverless Network Endpoint Group (NEG)

This setup is designed for modern web applications requiring a managed database backend, serverless scalability, and a robust global entry point.

## Prerequisites

To use this configuration, you need:

-   A GCP Account with billing enabled.
-   The `gcloud` CLI installed and authenticated (`gcloud auth application-default login`).
-   Terraform installed (version >= 1.0).
-   A container image pushed to a registry accessible by Cloud Run (e.g., Artifact Registry, Container Registry, Docker Hub).

## Deployment

1.  **Clone the repository** (if you haven't already) and navigate into the project directory.

2.  **Initialize Terraform**: This downloads the required providers.

    ```bash
    terraform init
    ```

3.  **Review the plan**: This command shows you exactly what resources Terraform will create, modify, or destroy.

    ```bash
    terraform plan
    ```

4.  **Apply the configuration**: If the plan is acceptable, apply it.

    ```bash
    terraform apply
    ```
    Type `yes` when prompted to confirm.

Terraform will provision the resources and output important information upon completion.

## Variables

The `main.tf` file uses variables to allow customization of resource names, database settings, Cloud Run image, region, etc. You can override the default values by creating a `terraform.auto.tfvars` file in the root directory (e.g., `terraform.auto.tfvars`) and setting variable values there.

```terraform
# Example terraform.auto.tfvars
resource_name = "my-app-prod"
db_tier = "db-standard-2"
cloudrun_image = "gcr.io/your-project-id/your-production-image:latest"
cloudrun_location = "us-central1"
allow_unauthenticated_cloudrun = false # Production apps usually require authentication
```

## Outputs

After `terraform apply`, important information about the deployed infrastructure, such as the Load Balancer IP address and Cloud Run service URL, is available as outputs. You can view them by running:

```bash
terraform output
```

## Destroying Resources

To tear down all resources created by this configuration, run:

```bash
terraform destroy
```

Type `yes` when prompted. **Use this command with caution as it will delete your cloud resources.**

## Security Considerations

**IMPORTANT:** The provided `main.tf` might include commented-out examples of using service account keys for authentication (`credentials = file(...)`). **Using service account keys directly and especially committing them to version control is a significant security risk and NOT recommended for production environments.** Prefer using GCP Workload Identity Federation or GKE Workload Identity to allow your applications to access GCP services securely without managing keys.

Additionally, ensure you restrict authorized networks for your Cloud SQL instance and configure VPC connectors for private communication between Cloud Run and Cloud SQL in a production setup.