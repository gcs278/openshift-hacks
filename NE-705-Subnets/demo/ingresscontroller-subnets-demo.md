# A Demo of IngressController Subnets API in 4.17

<!-- @hook show_editor EDITOR -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

## A Demo of IngressController Subnets API in 4.17

Preparing environment...

<!-- @noshow --> 

```bash
oc delete -n openshift-ingress-operator ingresscontroller demo &> /dev/null
```

Let's demo the new IngressController Subnet API that was introduced in 4.17.

Two new API fields are introduced for the IngressController:

- `spec.endpointPublishingStrategy.loadBalancer.providerParameters.aws.classicLoadBalancer.subnets`
- `spec.endpointPublishingStrategy.loadBalancer.providerParameters.aws.networkLoadBalancer.subnets`

<!-- @wait_clear -->

The `subnets` structure is common between them, and can accept a list of subnet names and/or a list of subnet ids.

```bash
#@notypeout
oc explain ingresscontroller.spec.endpointPublishingStrategy.loadBalancer.providerParameters.aws.classicLoadBalancer.subnets
```

Now, let's do a demo. In order to create an IngressController with subnets, we need to first discover what the subnets are.

We will do this in a "hacky" way and grep the `MachineSet` objects for the private subnets names, and replace private with public.

```bash
export SUBNETS=$(oc get machinesets.machine.openshift.io -A -o yaml | grep -i subnet-private | awk '{print $2}' | sed 's/private/public/g')

echo $SUBNETS | tr ' ' '\n'

export TEST_DOMAIN="demo.$(oc get dnses cluster -o jsonpath={.spec.baseDomain})"
./generate-ingresscontroller-yaml.sh > ingresscontroller-subnets.yaml

bat --paging never ingresscontroller-subnets.yaml

oc apply -f ingresscontroller-subnets.yaml
```

Let's examine the Service to see if the `service.beta.kubernetes.io/aws-load-balancer-subnets` is present:

```bash
oc get -n openshift-ingress service router-demo -o yaml | bat --paging never --language yaml
```

Next, let's examine the IngressController's status. The status reflects the *actual* value of the subnets (i.e. the current subnet annotation value):

```bash
oc get ingresscontroller -n openshift-ingress-operator -o yaml | bat --paging never --language yaml
echo
```

<!-- @wait_clear -->

Okay. We've specified subnets successfully. How do we change them?

When you update a subnet, the IngressController does *not* automatically update the annotations on the service. You must delete the service
so that the Ingress Operator recreates the service.

This is an existing pattern we used for Ingress Controller Scope: `spec.endpointPublishingStrategy.loadBalancer.scope`.

This is for a variety of reasons:
1. The CCM Doesn't Reconcile NLB Subnets Updates after creation.
2. To mitigate risks associated with cluster admins providing an invalid annotation value.
3. To mitigate upgrade compatibility issues.

<!-- @wait -->

So lets change the subnets and see what happens:

```bash
# This removes the subnets
oc -n openshift-ingress-operator patch ingresscontrollers/demo --type=merge --patch='{"spec":{"endpointPublishingStrategy":{"type":"LoadBalancerService","loadBalancer":{"providerParameters":{"type":"AWS","aws":{"type":"Classic","classicLoadBalancer":{"subnets":null}}}}}}}'
```

Now let's examine the IngressController's status again:

```bash
oc get ingresscontroller -n openshift-ingress-operator demo -o jsonpath='{.status.conditions[?(@.type=="Progressing")]}' | yq -P
```

Okay, it's `Progressing=True` and it has provided instructions. Let's follow the instructions to effectuate the subnet removal:

```bash
oc -n openshift-ingress delete svc/router-demo
```

Now, let's wait for the status to clear:
```bash
oc get ingresscontroller -n openshift-ingress-operator demo -o jsonpath='{.status.conditions[?(@.type=="Progressing")]}' | yq -P
```

Great! What happens if you change the load balancer type which *also results* in a subnet change?

Let's add some subnets to the `networkLoadBalancer` parameters, then switch the LB type, but
at the same time, let's make the new subnet invalid:

```bash
#
# We are currently Classic type, so adding subnets to networkLoadBalancer is a NO-OP.
oc -n openshift-ingress-operator patch ingresscontrollers/demo --type=merge --patch='{"spec":{"endpointPublishingStrategy":{"type":"LoadBalancerService","loadBalancer":{"providerParameters":{"type":"AWS","aws":{"type":"Classic","networkLoadBalancer":{"subnets":{"ids":null,"names":["invalid-subnet"]}}}}}}}}'

# So our current IngressController spec looks like:
oc get ingresscontroller -n openshift-ingress-operator demo -o jsonpath='{.spec}' | yq -P | bat --paging never --language yaml

# Progressing status *does not change*.
oc get ingresscontroller -n openshift-ingress-operator demo -o jsonpath='{.status.conditions[?(@.type=="Progressing")]}' | yq -P

# Update to NLB now.
oc -n openshift-ingress-operator patch ingresscontrollers/demo --type=merge --patch='{"spec":{"endpointPublishingStrategy":{"type":"LoadBalancerService","loadBalancer":{"providerParameters":{"type":"AWS","aws":{"type":"NLB"}}}}}}'
```

Now, since we update the LB type, we should see a Progressing status:
```bash
oc get ingresscontroller -n openshift-ingress-operator demo -o jsonpath='{.status.conditions[?(@.type=="Progressing")]}' | yq -P
```

Let's effectuate the subnet change by deleting the service:
```bash
oc -n openshift-ingress delete svc/router-demo
```

But wait, what's that? Did the load balancer fail to provision due to an invalid subnet?

```bash
oc get ingresscontroller -n openshift-ingress-operator demo -o jsonpath='{.status.conditions[?(@.type=="LoadBalancerReady")]}' | yq -P
```

The end!

<!-- @wait -->
