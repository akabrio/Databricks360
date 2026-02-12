#!/usr/bin/env bash
set -euo pipefail

rgname="$1"
tenantid="$2"
clientid="$3"
clientsecret="$4"
repourl="$5"
ghuser="$6"
ghpat="$7"

# (Optional) protect against CRLF if this file ever gets checked out wrong
# NOTE: this line only works if you run it from another script before this one.
# sed -i 's/\r$//' "$0"

echo "rgname: $rgname"
echo "tenant: $tenantid"
echo "client id: ****"
echo "repourl: $repourl"
echo "ghuser: $ghuser"

# Ensure databricks cli is available (depends on how you installed it)
export PATH="$HOME/.local/bin:$PATH"
databricks version || true

# Get workspace URL + ARM resource ID (first workspace in RG)
workspacestuff="$(az databricks workspace list -g "$rgname" --query "[0].{url:workspaceUrl,id:id}" -o tsv)"
if [[ -z "$workspacestuff" ]]; then
  echo "No Databricks workspace found in RG: $rgname"
  exit 1
fi

workspaceUrl="$(echo "$workspacestuff" | awk '{print $1}')"
workspaceArmId="$(echo "$workspacestuff" | awk '{print $2}')"

echo "workspaceUrl: $workspaceUrl"
echo "workspaceArmId: $workspaceArmId"

# Unified Auth env vars
export DATABRICKS_HOST="https://${workspaceUrl}"
export DATABRICKS_AZURE_RESOURCE_ID="${workspaceArmId}"
export ARM_CLIENT_ID="${clientid}"
export ARM_CLIENT_SECRET="${clientsecret}"
export ARM_TENANT_ID="${tenantid}"

# Debug (non-secret) - shows what auth method it will use
databricks auth env --output json || true

# Git credentials
creds="$(databricks git-credentials list --output json)"
if [[ "$creds" == "[]" ]]; then
  echo "No git credentials found. Creating…"
  databricks git-credentials create --json "{
    \"personal_access_token\": \"${ghpat}\",
    \"git_username\": \"${ghuser}\",
    \"git_provider\": \"gitHub\"
  }"
else
  echo "Git credentials exist. Skipping create."
fi

# Repo create
repoName="$(basename "$repourl")"
repoName="${repoName%.git}"
workspaceRepoPath="/Repos/${ghuser}/${repoName}"

echo "Creating repo at: $workspaceRepoPath"
databricks repos create --url "$repourl" --provider gitHub --path "$workspaceRepoPath"

echo "finished"