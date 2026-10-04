#!/usr/bin/env bash
# Demonstrates that the Elasticsearch deployment is functioning AND secure.
# Every check prints PASS/FAIL; the script exits non-zero if any check fails.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="$ROOT/ansible/.secrets"
CA="$SECRETS/ca.crt"
ELASTIC_PW="$(cat "$SECRETS/elastic_password")"
DEMO_PW="$(cat "$SECRETS/demo_password")"

IPS=()  # portable to macOS bash 3.2 (no mapfile)
while IFS= read -r ip; do IPS+=("$ip"); done < <(terraform -chdir="$ROOT/terraform" output -json nodes | jq -r '.[].public_ip')
NODE_COUNT=${#IPS[@]}
IP="${IPS[0]}"
URL="https://$IP:9200"
INDEX="demo-books"

pass=0; fail=0
green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
check() { # check "<description>" <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then green "PASS  $desc"; pass=$((pass+1));
  else red "FAIL  $desc"; fail=$((fail+1)); fi
}
status() { # status <expected-http-code> <curl args...>
  local want="$1"; shift
  [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$@")" == "$want" ]]
}
es()   { curl -sf --max-time 15 --cacert "$CA" -u "elastic:$ELASTIC_PW" "$@"; }
demo() { curl -s  --max-time 15 --cacert "$CA" -u "demo:$DEMO_PW" -H 'Content-Type: application/json' "$@"; }

echo "== Target: $NODE_COUNT node(s), testing via $URL"
echo
echo "== 1. Encryption in transit"
check "plain HTTP is refused on 9200"              bash -c "! curl -s --max-time 5 http://$IP:9200"
check "TLS certificate validates against our CA"   curl -s --max-time 15 --cacert "$CA" -o /dev/null "$URL"
check "TLS without trusting our CA is rejected"    bash -c "! curl -s --max-time 15 -o /dev/null $URL"
check "negotiated protocol is TLS 1.2+"            bash -c "echo | openssl s_client -connect $IP:9200 -CAfile '$CA' 2>/dev/null | grep -Eq 'Protocol *: *TLSv1\.[23]|TLSv1\.[23],'"

echo
echo "== 2. Authentication & authorization"
check "anonymous request -> 401"                   status 401 --cacert "$CA" "$URL"
check "wrong password -> 401"                      status 401 --cacert "$CA" -u elastic:wrong "$URL"
check "elastic superuser -> 200"                   status 200 --cacert "$CA" -u "elastic:$ELASTIC_PW" "$URL"
check "demo user denied cluster APIs -> 403"       status 403 --cacert "$CA" -u "demo:$DEMO_PW" "$URL/_cat/nodes"
check "demo user denied other indices -> 403"      status 403 --cacert "$CA" -u "demo:$DEMO_PW" -X PUT "$URL/secret-index"

echo
echo "== 3. Network exposure"
check "transport port 9300 unreachable from internet" bash -c "! nc -z -w 5 $IP 9300"

echo
echo "== 4. Cluster health"
es "$URL" | jq '{name, cluster_name, version: .version.number}'
es "$URL/_cat/nodes?v&h=name,ip,node.role,master,heap.percent,ram.percent"
check "cluster status is green"                    bash -c "curl -sf --cacert '$CA' -u 'elastic:$ELASTIC_PW' '$URL/_cluster/health' | jq -e '.status==\"green\"'"
check "all $NODE_COUNT nodes joined"               bash -c "curl -sf --cacert '$CA' -u 'elastic:$ELASTIC_PW' '$URL/_cluster/health' | jq -e '.number_of_nodes==$NODE_COUNT'"

echo
echo "== 5. Index, search (as least-privilege demo user)"
REPLICAS=$(( NODE_COUNT > 1 ? 1 : 0 ))
demo -X DELETE "$URL/$INDEX" >/dev/null   # demo has no delete_index; ignored if it fails
demo -X PUT "$URL/$INDEX" -d "{\"settings\":{\"number_of_shards\":1,\"number_of_replicas\":$REPLICAS}}" >/dev/null
check "index a document"                           bash -c "curl -sf --cacert '$CA' -u 'demo:$DEMO_PW' -H 'Content-Type: application/json' -X PUT '$URL/$INDEX/_doc/1?refresh=true' -d '{\"title\":\"Designing Data-Intensive Applications\",\"author\":\"Martin Kleppmann\"}'"
for ip in "${IPS[@]}"; do
  check "search finds the document via node $ip"   bash -c "curl -sf --cacert '$CA' -u 'demo:$DEMO_PW' -H 'Content-Type: application/json' 'https://$ip:9200/$INDEX/_search' -d '{\"query\":{\"match\":{\"title\":\"data\"}}}' | jq -e '.hits.total.value>=1'"
done
if (( NODE_COUNT > 1 )); then
  echo
  es "$URL/_cat/shards/$INDEX?v&h=index,shard,prirep,state,node"
fi

echo
echo "== Result: $pass passed, $fail failed"
(( fail == 0 ))
