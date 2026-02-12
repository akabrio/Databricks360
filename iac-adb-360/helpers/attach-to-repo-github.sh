#!/usr/bin/env bash
set -euo pipefail

rgname="$1"
tenantid="$2"
clientid="$3"
clientsecret="$4"
repourl="$5"
ghuser="$6"
ghpat="$7"

echo "rgname: $rgname"
echo "tenant: $tenantid"
echo "client id: ****"
echo "repourl: $repourl"
echo "ghuser: $ghuser"

# Ensure databricks CLI is available (depends on how you installed it)
export PATH="$HOME/.local/bin:$PATH"
databricks version

# Get workspace URL + ARM resource ID (first workspace in RG)
workspacestuff="$(az databricks workspace list -g "$rgname" --query "[0].[workspaceUrl,id]" -o tsv)"
if [[ -z "${workspacestuff:-}" ]]; then
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

# Debug (non-secret)
databricks auth env --output json || true

# Git credentials (avoid JSON escaping issues by using a temp file)
creds="$(databricks git-credentials list --output json)"
if [[ "$creds" == "[]" ]]; then
  echo "No git credentials found. Creating…"
  tmpjson="$(mktemp)"
  cat > "$tmpjson" <<EOF
{
  "personal_access_token": "${ghpat}",
  "git_username": "${ghuser}",
  "git_provider": "gitHub"
}
EOF
  databricks git-credentials create --json @"$tmpjson"
  rm -f "$tmpjson"
else
  echo "Git credentials exist. Skipping create."
fi

# Repo create (skip if already exists)
repoName="$(basename "$repourl")"
repoName="${repoName%.git}"
workspaceRepoPath="/Repos/${ghuser}/${repoName}"

echo "Ensuring repo at: $workspaceRepoPath"
if databricks repos create --url "$repourl" --provider gitHub --path "$workspaceRepoPath" 2>/dev/null; then
  echo "Repo created."
else
  echo "Repo may already exist. Listing to verify..."
  databricks repos list --output json | head -c 2000 || true
  echo "Continuing."
fi

echo "finished"