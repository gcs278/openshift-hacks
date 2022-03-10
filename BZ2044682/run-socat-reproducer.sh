set -x
#/usr/bin/socat TCP4-LISTEN:8676,reuseaddr,fork EXEC:'/bin/bash -c \"printf \\\"HTTP/1.0 200 OK\\nset-cookie: X=Y\\\nset-cookie2: A=B\\\nset-cookie: P=Q\\\nset-cookie2: M=N\\\"; sed -e \\\"/^\r/q\\\"\"'
socat -T 1 -d -d tcp-l:8676,reuseaddr,fork,crlf system:"echo -e \"\\\"HTTP/1.0 200 OK\\\nDocumentType: text/html\\\nset-cookie: X=Y\\\nset-cookie2: A=B\\\nset-cookie: P=Q\\\nset-cookie2: M=N\\\n\\\n<html>date: \$\(date\)<br>server:\$SOCAT_SOCKADDR:\$SOCAT_SOCKPORT<br>client: \$SOCAT_PEERADDR:\$SOCAT_PEERPORT\\\n<pre>\\\"\"; cat; echo -e \"\\\"\\\n</pre></html>\\\"\""
