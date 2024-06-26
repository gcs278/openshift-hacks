# A Demo of a Route with SHA-1 Upgradeable=False in 4.15

<!-- @hook show_editor EDITOR -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

## A Demo of a Route with SHA-1 Upgradeable=False in 4.15

Let's demo what happens when you have a Route with a SHA-1 Certificate in 4.15.18+ clusters.

First, let's check our cluster version to make sure we are running 4.15.18+:

```bash
oc version
```

Next, let's create a Route with a SHA-1 certificate and see what happens.

First, we will need to generate a SHA-1 certificate:

```bash
#@notypeout
openssl req -x509 -sha1 -newkey rsa:1024 -days 3650 -keyout certs/sha1CA.key -out certs/sha1CA.crt -addext "keyUsage=cRLSign, digitalSignature, keyCertSign" -addext                          "extendedKeyUsage=serverAuth,clientAuth" -nodes -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleCA.com/emailAddress=example@example.com'
#@notypeout
openssl req -newkey rsa:1024 -nodes -keyout certs/sha1.key -out certs/sha1.csr -subj '/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'
#@notypeout
openssl x509 -req -days 3650 -sha1 -in certs/sha1.csr -CA certs/sha1CA.crt -CAcreateserial -CAkey certs/sha1CA.key -extensions ext -extfile <(echo $'[ext]\nbasicConstraints = CA:            FALSE\nsubjectKeyIdentifier = none\nauthorityKeyIdentifier = none\nextendedKeyUsage=serverAuth,clientAuth\nkeyUsage=nonRepudiation, digitalSignature, keyEncipherment') -out certs/sha1.crt
```
And just to be sure, let's prove it's a SHA-1 Cert:

```bash
openssl x509 -noout -text -in 'certs/sha1.crt' | grep -i sha1
```

Now, let's create a route with this SHA-1 Cert:

```bash
bat route-sha1.yaml --paging never

oc apply -f route-sha1.yaml
```

Let's examine the route's status conditions:

```bash
oc get route route-sha1 -o yaml | bat --paging never --language yaml
```

Okay, we have `UpgradeRouteValidationFailed`. Good.

Next, let's see if the Ingress Operator created that Admin Gate:

```bash
oc get -n openshift-config-managed configmap admin-gates -o yaml | bat --paging never --language yaml
```

Nice. Let's examine the upgradeable status as reported by `oc adm`:

```bash
oc adm upgrade
```

Okay, we can't upgrade. That's expected.

Now, say I'm a Cluster Admin that wants to upgrade anyways and I don't care about this route
breaking in 4.16.

I can create an admin ack to acknowledge and resolve the upgradeable condition back to True:

```bash
oc patch configmap admin-acks -n openshift-config --type=merge -p='{"data": {"ack-4.15-route-config-not-supported-in-4.16": "true"}}'
```

Now, let's examine the upgradeable status:

```bash
oc adm upgrade
```

Nice. It's upgradeable again!
