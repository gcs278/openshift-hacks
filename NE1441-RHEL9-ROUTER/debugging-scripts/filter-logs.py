#!/usr/bin/env python3
import re
import sys
from prettytable import PrettyTable

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
    return route_map

# Function to parse the log file and enrich it with route names
def parse_log(file_path, route_map):
    table = PrettyTable()
    table.field_names = ["Line", "Timestamp", "Route Name", "Lease State", "Action", "Event"]
    table.align["Event"] = "l"  # Left align the event descriptions for better readability
    table.align["Alert"] = "l"

    uuid_pattern = re.compile(r'([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})')
    name_pattern = re.compile(r'"name"="([^"]+)"')
    msg_pattern = re.compile(r'"msg"="([^"]+)"')  # Pattern to capture content within msg=""
    event_pattern = re.compile(r'"event"="([^"]+)"') 
    action_pattern = re.compile(r'"action"="([^"]+)"')
    duration_pattern = re.compile(r'"duration"=(\d+)')  # Pattern to capture content within msg=""
    action_in_key_pattern = re.compile(r'"key"="[^_]+_([^"]+)"')  # Pattern to capture content within msg=""

    files_of_interest = ['writerlease.go', 'status.go', 'contention.go', 'router_controller.go']

    previous_lease_state = "Election"
    lease_state = "Election"
    line_count = 0
    follower_patterns = [
        "skipped update due to another process altering the route with a different ingress status value",
        "updating route status failed due to write conflict",
        "route was deleted before we could update status"
    ]
    leader_pattern = "updated route status"
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

                    if not route_name:
                        key_match = uuid_pattern.search(details)
                        route_name = route_map.get(key_match.group(1), "Unknown Route") if key_match else "N/A"

                    msg_content = msg_pattern.search(details)
                    event_content = event_pattern.search(details)
                    msg_details = msg_content.group(1) if msg_content else "No message found"
                    duration_content = duration_pattern.search(details)
                    action_content = action_pattern.search(details)
                    action_in_key_content = action_in_key_pattern.search(details)

                    if any(fp in details for fp in follower_patterns):
                        lease_state = "Follower"
                    elif leader_pattern in details:
                        lease_state = "Leader"

                    display_lease_state = lease_state
                    if lease_state != previous_lease_state:
                        display_lease_state = f"{RED}{lease_state}{RESET}"

                    # Add a definition for the green color
                    GREEN = '\033[92m'

                    # Further down in your code where you handle event details
                    if 'updated route status' in msg_details:
                        msg_details = f"{GREEN}{msg_details}{RESET}"

                    event_details = event_content.group(1) if event_content else ""
                    if event_details:
                        msg_details = msg_details + " [" + event_details + "]"

                    duration = duration_content.group(1) if duration_content else ""
                    if duration:
                        duration_seconds = float(duration_content.group(1)) / 1_000_000_000
                        msg_details += f" [Duration: {duration_seconds:.2f}s]" 

                    action_details = ""
                    action = action_content.group(1) if action_content else ""
                    if action:
                        action_details = f"{action}"  

                    action_in_key = action_in_key_content.group(1) if action_in_key_content else ""
                    if action_in_key:
                        action_details = f"{action_in_key}"  

                    action_details = action_details.replace("UnservableInFutureVersions", "UIFV")

                    table.add_row([line_count, timestamp, route_name, display_lease_state, action_details, msg_details])
                    previous_lease_state = lease_state  # Update the previous state

    return table

# First, build the route map
route_map = build_route_map(log_file_path)

# Now, parse the log with the route map
table = parse_log(log_file_path, route_map)
print(table)
