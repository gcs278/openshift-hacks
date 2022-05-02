#!/bin/bash

function graph_args() {
  num=$1
  PROM_GRAPH_ARGS="g${num}.range_input=${diff_string}&g${num}.end_input=${END_TIME_URL}&g${num}.moment_input=${END_TIME_URL}"
  echo "$PROM_GRAPH_ARGS"
}

log=$1
if [[ "$log" == "" ]]; then
  echo "ERROR: You need to provide a log file"
  exit 1
fi

START_TIME=$(grep "time=" $log | head -1 | awk -F\" '{print $2}')
END_TIME=$(date -u -d "$(grep "Removing touchstone" $log | tail -1 | awk '{print $3"-"$2"-"$6" "$4" UTC"}')" +"%Y-%m-%d %H:%M:%S")

START_SEC="$(date -d "$START_TIME" +%s)"
END_SEC="$(date -d "$END_TIME" +%s)"

diff_sec=$((END_SEC-START_SEC))
diff_hour=$(bc <<< "scale=1; $diff_sec / 60 / 60")

# Round up
diff_string=$(printf '%dh%dm%ds\n' $((diff_sec/3600)) $((diff_sec%3600/60)) $((diff_sec%60)))
echo $diff_string

END_TIME_URL=$(echo $END_TIME | jq -sRr @uri)

GRAPH=0
PROM_URL="https://prometheus-k8s-openshift-monitoring.apps.bm.rdu2.scalelab.redhat.com/graph"
MAXCONN="g0.expr=sum(haproxy_frontend_current_sessions)%20&g0.tab=0&g0.stacked=1&g0.show_exemplars=0&$(graph_args 0)&g0.step_input=10"
READY_RESTARTS="g1.expr=kube_pod_status_ready%7Bnamespace%3D%22openshift-ingress%22%7D%20or%20sum(kube_pod_container_status_restarts_total%7Bnamespace%3D%22openshift-ingress%22%7D)&g1.tab=0&g1.stacked=0&g1.show_exemplars=0&$(graph_args 1)"
ROUTER_MEMORY="g2.expr=container_memory_usage_bytes%7Bnamespace%3D%22openshift-ingress%22%2Ccontainer%3D%22router%22%7D&g2.tab=0&g2.stacked=0&g2.show_exemplars=0&$(graph_args 2)&g2.step_input=10"
HAPROXY_ERRORS="g3.expr=sum(haproxy_server_connection_errors_total)&g3.tab=0&g3.stacked=0&g3.show_exemplars=0&$(graph_args 3)"
LATENCY="g4.expr=haproxy_server_http_average_response_latency_milliseconds&g4.tab=0&g4.stacked=0&g4.show_exemplars=0&$(graph_args 4)"

URL="${PROM_URL}?${MAXCONN}&${READY_RESTARTS}&${ROUTER_MEMORY}&${HAPROXY_ERRORS}&${LATENCY}"

echo $URL

xdg-open $URL
