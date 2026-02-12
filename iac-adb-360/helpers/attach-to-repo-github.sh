#!/bin/bash
set -euo pipefail

resourcegroupname="$1"
tenantid="$2"
clientid="$3"
clientsecret="$4"
repourl="$5"
ghuser="$6"
ghpat="$7"

echo "rgname      : $resourcegroupname"
echo "tenant      : $tenantid"
echo "client id   : $clientid"
echo "repourl     : $repourl"
echo "ghuser      : $ghuser"
# DO NOT echo secrets

# --- Get first workspace in RG (better: filter by workspace name if you can) ---
# Output: workspaceUrl<TAB>id
workspacestuff="$(az databricks workspace list -g "$resourcegroupname" --query "[0].{url:workspaceUrl, id:id}" -o tsv)"

if [ -z "$workspacestuff" ]; then
  echo "No Databricks workspace found in resource group: $resourcegroupname"
  exit 1
fi

workspaceUrl="$(echo "$workspacestuff" | awk '{print $1}')"
workspaceArmId="$(echo "$workspacestuff" | awk '{print $2}')"

echo "workspaceUrl: $workspaceUrl"
echo "workspaceArmId: $workspaceArmId"

# --- Auth for Databricks CLI via Azure (OIDC/SP already logged in by AzureCLI task) ---
export ARM_CLIENT_ID="$clientid"
export ARM_CLIENT_SECRET="$clientsecret"
export ARM_TENANT_ID="$tenantid"
export DATABRICKS_AZURE_RESOURCE_ID="$workspaceArmId"

# Optional but useful for some CLI flows:
export DATABRICKS_HOST="https://${workspaceUrl}"

# --- Ensure git credentials exist ---
creds="$(databricks git-credentials list --output json || true)"

if [ -z "$creds" ] || [ "$creds" = "[]" ]; then
  echo "No git credentials found; creating..."
  databricks git-credentials create --json "{
    \"personal_access_token\": \"${ghpat}\",
    \"git_username\": \"${ghuser}\",
    \"git_provider\": \"gitHub\"
  }"
else
  echo "Git credentials already exist; skipping create."
fi

# --- Create repo in workspace ---
# Choose a deterministic workspace path
repoName="$(basename "$repourl")"
repoName="${repoName%.git}"
workspaceRepoPath="/Repos/${ghuser}/${repoName}"

echo "Creating repo at workspace path: $workspaceRepoPath"

# NOTE: CLI syntax varies by version; this is the common pattern for modern databricks CLI.
# If your CLI complains, I’ll adapt to the exact version string from `databricks --version`.
databricks repos create --url "$repourl" --provider gitHub --path "$workspaceRepoPath" || {
  echo "Repo create failed. If it already exists, you may want to update instead."
  echo "Trying to list existing repos..."
  databricks repos list --output json || true
  exit 1
}

echo "finished"