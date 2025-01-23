#!/bin/bash

# Generate CA Cert
#openssl req -x509 -sha256 -newkey rsa:1024 -days 3650 -keyout exampleca.key -out exampleca.crt -addext "keyUsage=cRLSign, digitalSignature, keyCertSign" -addext "extendedKeyUsage=serverAuth, clientAuth" -nodes -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com'

# Generate CSR
openssl req -newkey rsa:1024 -nodes -keyout testCertificateRsaSha1.key -out example.csr -subj '/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'

# Generate cert
openssl x509 -req -days 3650 -sha1 -in example.csr -CA exampleca.crt -CAcreateserial -CAkey exampleca.key -extensions ext -extfile <(echo $'[ext]\nbasicConstraints = CA:FALSE') -out testCertificateRsaSha1.crt
