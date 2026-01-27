# Demo Instructions for https://github.com/openshift/cluster-ingress-operator/pull/1347

## To show the migration

oc_scale_cvo 0
oc_gwapi_create_http_demo
oc_ingress_scale_operator 0
./ingress-operator start-gatewayclass


## To show revertion back to sail
stop ./ingress-operator
oc_ingress_scale_operator 1
