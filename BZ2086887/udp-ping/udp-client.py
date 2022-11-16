#!/usr/bin/env python

import datetime
import time
import sys
import socket

host = "udp-ping-server.default.svc.cluster.local" #set to server ip or hostname
port = 25050

number_of_pings = 40
timeout = 2
sleep_time = 1
message_bytes = 256

min_ping = 999999
max_ping = 0
ping_count = 0
ping_received = 0
avg_ping = 0
warning_time=5

clientSocket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
clientSocket.settimeout(timeout)

message = bytearray([1] * message_bytes)

def show_summary():
    total_time = (time.time() - time_start) * 1000

    print('--- %s udp ping statistics ---' % (host))
    print('%d packets transmitted, %d received, %0.0f%% packet loss, time %0.0fms' % (ping_count, ping_received, (ping_count - ping_received) / ping_count * 100, total_time))
    print('rtt min/avg/max/mdev = %0.3f/%0.3f/%0.3f/%0.3f ms' % (min_ping, avg_ping / ping_count, max_ping, max_ping - min_ping))
    sys.exit()

time_start = time.time()

print(f"Starting ping to host {host} on port {port}...")

seq=0
while True:
    try:
        clientSocket.sendto(message, (host, port))
        start = time.time()
        data, server = clientSocket.recvfrom(2048)
        end = time.time()
        elapsed = (end - start) * 1000
        if elapsed < min_ping: min_ping = elapsed
        if elapsed > max_ping: max_ping = elapsed
        ping_count += 1
        ping_received += 1
        avg_ping += elapsed
        jitter = elapsed - min_ping
        if elapsed > warning_time:
          print('%s: Time exceeded %d ms: received %s bytes from %s udp_seq=%d time=%0.1f ms jitter=%0.2f ms' % (datetime.datetime.now(), warning_time, len(data), host, seq, elapsed, jitter))
        time.sleep(sleep_time)
    except socket.timeout as e:
        print('%s: udp_seq=%d REQUEST TIMED OUT' % (datetime.datetime.now(), seq))
    except KeyboardInterrupt:
        show_summary()
    seq=seq+1

show_summary()
