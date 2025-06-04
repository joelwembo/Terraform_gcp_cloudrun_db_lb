#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Ensure that pipelines fail on the first command that fails.
set -o pipefail

echo "--- Starting Terraform Workflow ---"

# 1. Initialize Terraform
# Initializes the working directory containing Terraform configuration files.
# -input=false prevents Terraform from prompting for input.
echo "[+] Initializing Terraform..."
terraform init -input=false
echo "[+] Terraform initialization complete."

# 2. Validate Terraform Configuration
# Checks whether the configuration is syntactically valid and internally consistent.
echo "[+] Validating Terraform configuration..."
terraform validate
echo "[+] Terraform configuration validation successful."

# 3. Create Terraform Plan
# Creates an execution plan, determining what actions are necessary to achieve the desired state.
# -out=tfplan saves the plan to a file to be used by apply.
# -input=false prevents prompts.
echo "[+] Creating Terraform execution plan..."
terraform plan -out=tfplan -input=false
echo "[+] Terraform plan created successfully (tfplan)."

# 4. Apply Terraform Plan
# Applies the changes required to reach the desired state of the configuration.
# -auto-approve skips interactive approval of the plan before applying.
# tfplan specifies the plan file to apply.
echo "[+] Applying Terraform plan..."
terraform apply -auto-approve -input=false tfplan
echo "[+] Terraform apply completed successfully."

# 5. Capture Terraform Outputs
# Reads output values from the Terraform state file and prints them in JSON format.
# Redirects the JSON output to a file named terraform_outputs.json.
echo "[+] Retrieving Terraform outputs..."
terraform output -json > terraform_output.json
if [ $? -ne 0 ]; then
    echo "[!] Error: Failed to retrieve Terraform outputs." >&2
    # Optionally clean up the plan file if output fails
    # rm -f tfplan
    exit 1
fi
echo "[+] Terraform outputs successfully retrieved and saved to terraform_output.json."

# Optional: Clean up the plan file after successful apply and output retrieval
# rm -f tfplan

echo "--- Terraform Workflow Completed Successfully ---"

exit 0
