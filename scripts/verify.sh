#!/usr/bin/env bash
# Demonstrates that the Elasticsearch deployment is functioning AND secure.
# Nodes are private, so API checks go through an SSM-backed SOCKS tunnel
# (scripts/tunnel.sh); exposure checks query the AWS API directly.
# Every check prints PASS/FAIL; the script exits non-zero if any check fails.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="$ROOT/ansible/.secrets"
CA="$SECRETS/ca.crt"
ELASTIC_PW="$(cat "$SECRETS/elastic_password")"
DEMO_PW="$(cat "$SECRETS/demo_password")"
export SOCKS_PORT="${SOCKS_PORT:-1080}"
PROXY="socks5h://127.0.0.1:$SOCKS_PORT"

TF="terraform -chdir=$ROOT/terraform"
REGION="$($TF output -raw region)"
SG="$($TF output -raw security_group_id)"
NODES_JSON="$($TF output -json nodes)"
IPS=(); IDS=()  # portable to macOS bash 3.2 (no mapfile)
while IFS= read -r v; do IPS+=("$v"); done < <(jq -r '.[].private_ip' <<<"$NODES_JSON")
while IFS= read -r v; do IDS+=("$v"); done < <(jq -r '.[].instance_id' <<<"$NODES_JSON")
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
c() { curl -s --max-time 15 -x "$PROXY" "$@"; }   # every API call goes through the tunnel
status() { # status <expected-http-code> <curl args...>
  local want="$1"; shift
  [[ "$(c -o /dev/null -w '%{http_code}' "$@")" == "$want" ]]
}
es()   { c -f --cacert "$CA" -u "elastic:$ELASTIC_PW" "$@"; }
demo() { c --cacert "$CA" -u "demo:$DEMO_PW" -H 'Content-Type: application/json' "$@"; }

"$ROOT/scripts/tunnel.sh" start >/dev/null || { red "could not open SSM tunnel"; exit 1; }
trap '"$ROOT/scripts/tunnel.sh" stop' EXIT

echo "== Target: $NODE_COUNT private node(s), testing via $URL (SSM tunnel)"
echo
echo "== 1. Network exposure (AWS API)"
check "no node has a public IP" \
  bash -c "[[ -z \"\$(aws ec2 describe-instances --region $REGION --instance-ids ${IDS[*]} --query 'Reservations[].Instances[].PublicIpAddress' --output text | tr -d '[:space:]')\" ]]"
check "security group allows no inbound traffic from any IP range" \
  bash -c "aws ec2 describe-security-group-rules --region $REGION --filters Name=group-id,Values=$SG --output json | jq -e '[.SecurityGroupRules[] | select(.IsEgress==false and (.CidrIpv4 or .CidrIpv6))] | length == 0'"
check "all $NODE_COUNT nodes are managed by SSM (operator access path)" \
  bash -c "aws ssm describe-instance-information --region $REGION --filters Key=InstanceIds,Values=$(IFS=,; echo "${IDS[*]}") --output json | jq -e '[.InstanceInformationList[] | select(.PingStatus==\"Online\")] | length == $NODE_COUNT'"

echo
echo "== 2. Encryption in transit"
check "plain HTTP is refused on 9200"              bash -c "! curl -s --max-time 5 -x $PROXY http://$IP:9200"
check "TLS certificate validates against our CA"   c --cacert "$CA" -o /dev/null "$URL"
check "TLS without trusting our CA is rejected"    bash -c "! curl -s --max-time 15 -x $PROXY -o /dev/null $URL"
check "negotiated protocol is TLS 1.2+"            bash -c "curl -sv --max-time 15 -x $PROXY --cacert '$CA' -o /dev/null $URL 2>&1 | grep -Eq 'SSL connection using TLSv1\.[23]'"

echo
echo "== 3. Authentication & authorization"
check "anonymous request -> 401"                   status 401 --cacert "$CA" "$URL"
check "wrong password -> 401"                      status 401 --cacert "$CA" -u elastic:wrong "$URL"
check "elastic superuser -> 200"                   status 200 --cacert "$CA" -u "elastic:$ELASTIC_PW" "$URL"
check "demo user denied cluster APIs -> 403"       status 403 --cacert "$CA" -u "demo:$DEMO_PW" "$URL/_cat/nodes"
check "demo user denied other indices -> 403"      status 403 --cacert "$CA" -u "demo:$DEMO_PW" -X PUT "$URL/secret-index"

echo
echo "== 4. Cluster health"
es "$URL" | jq '{name, cluster_name, version: .version.number}'
es "$URL/_cat/nodes?v&h=name,ip,node.role,master,heap.percent,ram.percent"
HEALTH="$(es "$URL/_cluster/health")"
check "cluster status is green"                    jq -e '.status=="green"' <<<"$HEALTH"
check "all $NODE_COUNT nodes joined"               jq -e ".number_of_nodes==$NODE_COUNT" <<<"$HEALTH"

echo
echo "== 5. Index, search (as least-privilege demo user)"
REPLICAS=$(( NODE_COUNT > 1 ? 1 : 0 ))
demo -X PUT "$URL/$INDEX" -d "{\"settings\":{\"number_of_shards\":1,\"number_of_replicas\":$REPLICAS}}" >/dev/null
check "index a document" \
  demo -f -X PUT "$URL/$INDEX/_doc/1?refresh=true" -d '{"title":"Designing Data-Intensive Applications","author":"Martin Kleppmann"}'
for ip in "${IPS[@]}"; do
  check "search finds the document via node $ip" \
    bash -c "curl -sf --max-time 15 -x $PROXY --cacert '$CA' -u 'demo:$DEMO_PW' -H 'Content-Type: application/json' 'https://$ip:9200/$INDEX/_search' -d '{\"query\":{\"match\":{\"title\":\"data\"}}}' | jq -e '.hits.total.value>=1'"
done
if (( NODE_COUNT > 1 )); then
  echo
  es "$URL/_cat/shards/$INDEX?v&h=index,shard,prirep,state,node"
fi

echo
echo "== Result: $pass passed, $fail failed"
(( fail == 0 ))
