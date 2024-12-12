# A Demo of an Istio BackendLBPolicy Proof-of-Concept

<!-- @hook show_editor EDITOR -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

## A Demo of an Istio BackendLBPolicy Proof-of-Concept

The goal of my Shift Week (Oct 28 - Nov 1) was to get proof of concept done for `BackendLBPolicy` in Istio.

POC PR: https://github.com/istio/istio/pull/53755
GEP: https://gateway-api.sigs.k8s.io/geps/gep-1619/

Development was all on a local Kind cluster (no OpenShift!).

Let's create our Kind cluster for Istio development, and so I can demo the POC:

```bash
kind create cluster
kubectl version
```

Next, let's get Istio running. I followed John Howard's https://github.com/howardjohn/local-istio-development repo `Local Istiod, remote proxy` instructions.

We will install ONLY the pieces of Istio we need so that we can run Istiod locally and the Envoy Proxy in the kind cluster.

Let's build Istio from source:

```bash
cd ~/src/github.com/istio/istio/
sudo make build
```

Next, let's install the Istiod resources (ClusterRoles, ConfigMaps, MutatingWebhook, Deployments, etc...) into the cluster via the "istiod" helm chart.

We will enable Istiod to be run "remotely" to tell it to not create the Istiod deployment.

```bash
kubectl create ns istio-system
helm install istiod ./manifests/charts/istio-control/istio-discovery/ -n istio-system --set istiodRemote.enabled=true
kubectl get configmaps -n istio-system
kubectl get svc -n istio-system
kubectl get pods -n istio-system
```

Just in case, let's install the Istio CRDs into the cluster:

```bash
helm install base ./manifests/charts/base/

kubectl get crd | grep istio
```

Okay. Now I think we are ready to run Istiod locally.

```bash
# Let's run this in a different tab...it doesn't work in the demosh shell
# PILOT_ENABLE_ALPHA_GATEWAY_API=true go run ./pilot/cmd/pilot-discovery discovery
read
```

Okay, we are running the Istiod control plane!

Now, in order to start creating Gateway API Gateways (which creates an Automatic Deployment), we must run John's `use-local-pilot` script, which replaces the Istiod endpoints to use our local running Istiod instance:

```bash
cat ~/src/github.com/gcs278/openshift-hacks/session-persistence/use_local_pilot.sh | bat --paging never --language sh
~/src/github.com/gcs278/openshift-hacks/session-persistence/use_local_pilot.sh
```

Next, let's install the Gateway API CRDs (experimental so we can use `BackendLBPolicy`):

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/experimental-install.yaml
```

Let's test out Istio's bookinfo example:

```bash
kubectl apply -f samples/bookinfo/gateway-api/bookinfo-gateway.yaml
kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml
kubectl get pods
```

Nice, our Envoy Proxy (Gateway) is running in the Kind cluster, while Istiod is running on my laptop.

There are ways to configure ingress into the Kind cluster (see https://kind.sigs.k8s.io/docs/user/ingress/), but I didn't have time to figure it out, so I just tested using a local curl pod in the cluster:

```bash
kubectl get pods
kubectl get svc
kubectl run curlpod --image=curlimages/curl sleep 99999
kubectl exec curlpod -- sh -c "curl -s bookinfo-gateway-istio/productpage" | head -10
kubectl delete -f samples/bookinfo/gateway-api/bookinfo-gateway.yaml
kubectl delete -f samples/bookinfo/platform/kube/bookinfo.yaml
```

Great, our bookinfo example is working. We've got a local development environment set up to develop with Istiod now!

Let's now demonstrate the BackendLBPolicy POC. First, let's create a Gateway, HTTPRoute, and a deployment that echo the POD's name (so we can demo session persistence):

```bash
cd ~/src/github.com/gcs278/openshift-hacks/session-persistence
cat gateway-example.yaml | bat --paging never --language yaml
cat deployment-example.yaml | bat --paging never --language yaml
kubectl apply -f gateway-example.yaml
kubectl apply -f deployment-example.yaml
kubectl get pods
# Mutiple pods running:
kubectl exec curlpod -- sh -c "for i in \$(seq 1 5); do curl -s gateway-sp-demo-istio; done"
```

Now, let's create the `BackendLBPolicy`:

```bash
cat backendLBPolicy-example.yaml | bat --paging never --language yaml
kubectl apply -f backendLBPolicy-example.yaml
kubectl get backendlbpolicies.gateway.networking.k8s.io lb-policy -o yaml | bat --paging never --language yaml
kubectl exec curlpod -- sh -c "curl -s gateway-sp-demo-istio -I"
```

Nice. We see the `set-cookie` header present. Let's prove that it's actually working:

```bash
#kubectl exec curlpod -- sh -c "curl -s gateway-sp-demo-istio  --cookie foo-session=<replace>"
read
```

Let's change the cookie TTL and see what happens:

```bash
kubectl patch backendLbPolicy lb-policy --type=merge -p '{"spec":{"sessionPersistence":{"absoluteTimeout":"10s"}}}'
kubectl exec curlpod -- sh -c "curl -s gateway-sp-demo-istio -I"
```

Let's make the cookie a `session` cookie. The `max-age` attribute should be removed:

```bash
cat backendLBPolicy-session.yaml | bat --paging never --language yaml
kubectl apply -f backendLBPolicy-session.yaml
kubectl get backendlbpolicies.gateway.networking.k8s.io lb-policy -o yaml | bat --paging never --language yaml
kubectl exec curlpod -- sh -c "curl -s gateway-sp-demo-istio -I"
```

Lastly, let's show header-based session persistence with `BackendLBPolicy`:

```bash
cat backendLBPolicy-header.yaml | bat --paging never --language yaml
kubectl apply -f backendLBPolicy-header.yaml
kubectl get backendlbpolicies.gateway.networking.k8s.io lb-policy -o yaml | bat --paging never --language yaml
kubectl exec curlpod -- sh -c "for i in \$(seq 1 5); do curl -s gateway-sp-demo-istio -H \"foo-session: 1234567890\"; done"
```

The end.
