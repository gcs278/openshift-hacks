#!/bin/bash

# RootCA
openssl req -x509 -sha1 -newkey rsa:2048 -days 3650 -keyout exampleca.key -out exampleca.crt -addext "keyUsage=cRLSign, digitalSignature, keyCertSign" -addext "extendedKeyUsage=serverAuth, clientAuth" -nodes -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com'

# intermediate
openssl req -newkey rsa:1024 -nodes -keyout example-inter.key -out example-inter.csr -subj '/CN=www.exampleinter.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'
openssl req -x509 -sha1 -days 3650 -in example-inter.csr -CA exampleca.crt -CAkey exampleca.key -out example-inter.crt -addext "keyUsage=cRLSign, digitalSignature, keyCertSign" -addext "extendedKeyUsage=serverAuth, clientAuth" -nodes -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleinter.com/emailAddress=example@example.com'

openssl req -newkey rsa:2048 -nodes -keyout example.key -out example.csr -subj '/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'
openssl x509 -req -days 3650 -sha256 -in example.csr -CA example-inter.crt -CAcreateserial -CAkey example-inter.key -extensions ext -extfile <(echo $'[ext]\nbasicConstraints = CA:FALSE\nsubjectKeyIdentifier = none\nauthorityKeyIdentifier = none\nextendedKeyUsage=serverAuth,clientAuth\nkeyUsage=nonRepudiation, digitalSignature, keyEncipherment') -out example.crt
