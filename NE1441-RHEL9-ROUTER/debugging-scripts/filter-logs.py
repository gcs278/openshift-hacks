#!/usr/bin/env python3
import re
import sys

# Check if the command line argument is provided
if len(sys.argv) < 2:
    print("Usage: python script.py <path_to_log_file>")
    sys.exit(1)

# Take the log file path from the first command line argument
log_file_path = sys.argv[1]



# Function to build the map from the log file
def build_route_map(file_path):
    route_map = {}
    # Updated regex to extract metadata.name and metadata.uid
    route_pattern = re.compile(r'"metadata":\{"name":"([^"]+)","namespace":"[^"]+","uid":"([^"]+)"')

    with open(file_path, 'r') as file:
        for line in file:
            match = route_pattern.search(line)
            if match:
                name, uid = match.groups()
                route_map[uid] = name  # Map UID to name
                # print(f"Route UID {uid} to Route Name {name}")

    return route_map

# Function to parse the log file and enrich it with route names
def parse_log(file_path, route_map):
    events_list = []
    uuid_pattern = re.compile(r'([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})')
    name_pattern = re.compile(r'"name"="([^"]+)"')
    files_of_interest = ['writerlease.go', 'status.go', 'contention.go']

    # Initialize lease state
    previous_lease_state = "Election"
    lease_state = "Election"
    line_count = 0
    # Patterns that signify transitions
    follower_patterns = [
        "skipped update due to another process altering the route with a different ingress status value",
        "updating route status failed due to write conflict",
        "route was deleted before we could update status"
    ]
    leader_pattern = "updated route status"
    # Define ANSI escape sequence for red font
    RED = '\033[91m'
    RESET = '\033[0m'

    with open(file_path, 'r') as file:
        for line in file:
            line_count += 1
            if any(f in line for f in files_of_interest):
                match = re.search(r'I(\d{4} \d{2}:\d{2}:\d{2}.\d{6})\s+\d+\s+(.*)', line)
                if match:
                    timestamp, details = match.groups()
                    name_match = name_pattern.search(details)
                    route_name = name_match.group(1) if name_match else None

                    # If no direct name, try to match UUID and lookup in route_map
                    if not route_name:
                        key_match = uuid_pattern.search(details)
                        route_name = route_map.get(key_match.group(1), "Unknown Route") if key_match else "N/A"
                    
                    # Check for state transitions
                    if any(fp in details for fp in follower_patterns):
                        lease_state = "Follower"
                    elif leader_pattern in details:
                        lease_state = "Leader"

                    # Check if there was a transition
                    alert =""
                    if lease_state != previous_lease_state:
                        alert = f"{RED}*** TRANSITION: {previous_lease_state} to {lease_state} ***{RESET}"

                    events_list.append((line_count, timestamp, route_name, details, lease_state, alert))
                    previous_lease_state = lease_state  # Update the previous state

    return events_list

# First, build the route map
route_map = build_route_map(log_file_path)

# Now, parse the log with the route map
events = parse_log(log_file_path, route_map)
for event in events:
    print(f"{event[0]}: [{event[1]}] [{event[2]}] [Lease: {event[4]}] {event[5]}\n\t[{event[3]}")

