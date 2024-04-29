#!/usr/bin/env python3
import re
import sys
import json
from prettytable import PrettyTable
import difflib

# Check if at least one log file path is provided
if len(sys.argv) < 2:
    print("Usage: python script.py <path_to_log_file> [path_to_other_log_files...]")
    sys.exit(1)

# ANSI color codes for output
colors = ['\033[92m', '\033[93m', '\033[94m', '\033[95m', '\033[96m']
color_map = {}

# Collect all log file paths
log_file_paths = sys.argv[1:]

# Function to extract the base name of the file (without extension)
def get_router_name(file_path):
    return file_path.split('/')[-1].split('.')[0]

# Function to build the global route map from multiple log files
def build_global_route_map(file_paths):
    global_route_map = {}
    route_pattern = re.compile(r'"metadata":\{"name":"([^"]+)","namespace":"[^"]+","uid":"([^"]+)"')
    for file_path in file_paths:
        with open(file_path, 'r') as file:
            for line in file:
                match = route_pattern.search(line)
                if match:
                    name, uid = match.groups()
                    global_route_map[uid] = name  # use the UID as a global identifier
    return global_route_map

def compare_route_data(data1, data2):
    # Use difflib to create a human-readable diff
    diff = difflib.unified_diff(
        data1.splitlines(keepends=True),
        data2.splitlines(keepends=True),
        fromfile='Data1',
        tofile='Data2',
        lineterm='',
        n=0
    )
    return ''.join(diff)

# Function to extract "Admitted" status
def get_admitted_statuses(route_data):
    admitted_statuses = []
    if len(route_data['status']) > 0:
        for ingress in route_data['status']['ingress']:
            if ingress['routerName'] == "routeadmission":
                for condition in ingress['conditions']:
                    if condition['type'] == 'Admitted':
                        admitted_statuses.append({
                            'routerName': ingress['routerName'],
                            'status': condition['status'],
                            'lastTransitionTime': condition['lastTransitionTime']
                        })
    return admitted_statuses

# Function to parse the log file and enrich it with route names
def parse_logs(file_paths, route_map):
    all_logs = []

    table = PrettyTable()
    if len(file_paths) > 1:
        table.field_names = ["Line", "Timestamp", "Router Name", "Route Name", "Contention", "#", "Lease State", "Action", "Event"]
    else:
        table.field_names = ["Line", "Timestamp", "Route Name", "Contention", "#", "Lease State", "Action", "Event"]

    table.align["Event"] = "l"  # Left align the event descriptions for better readability
    table.align["Alert"] = "l"

    uuid_pattern = re.compile(r'([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})')
    name_pattern = re.compile(r'"name"="([^"]+)"')
    msg_pattern = re.compile(r'"msg"="([^"]+)"')  # Pattern to capture content within msg=""
    event_pattern = re.compile(r'"event"="([^"]+)"') 
    action_pattern = re.compile(r'"action"="([^"]+)"')
    route_pattern = re.compile(r'"route"=({.*})')
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

    for index, file_path in enumerate(file_paths):
        contended_status_map = {}
        max_contended = False
        contentions = 0
        router_name = get_router_name(file_path)
        color_map[router_name] = colors[index % len(colors)]  # Assign a color to each router
        previous_route_data = {}  # To store previous data for comparison

        with open(file_path, 'r') as file:
            for line in file:
                line_count += 1
                if any(f in line for f in files_of_interest):
                    match = re.search(r'I(\d{4} \d{2}:\d{2}:\d{2}.\d{6})\s+\d+\s+(.*)', line)
                    if match:
                        timestamp, details = match.groups()
                        name_match = name_pattern.search(details)
                        route_match = route_pattern.search(details)
                        route_name = name_match.group(1) if name_match else None
                        route_data = route_match.group(1) if route_match else None
                        key_match = uuid_pattern.search(details)
                        uid = key_match.group(1) if key_match else ""

                        if not route_name:
                            route_name = route_map.get(uid, "Unknown Route") if key_match else "N/A"

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
                            # msg_details = msg_details + " [" + event_details + "]"
                            msg_details = msg_details + " [" + event_details + "]"

                        if route_data:
                            admitted_statuses = get_admitted_statuses(json.loads(route_data))
                            for admitted_status in admitted_statuses:
                                # status = 'T' if admitted_status['status'] == 'True' else 'F'
                                status = admitted_status['status']
                                msg_details += " " +admitted_status["routerName"] + f'={status}' # + f' {admitted_status["lastTransitionTime"]}'
                        
                        if route_name and route_data:
                            # Check if this route has previous data to compare against
                            if route_name in previous_route_data:
                                # Perform the diff
                                diff_output = compare_route_data(previous_route_data[route_name], json.dumps(json.loads(route_data), sort_keys=True, indent=4))
                                # msg_details += " " + diff_output
                            # Update the previous data with the new data
                            previous_route_data[route_name] = json.dumps(json.loads(route_data), sort_keys=True, indent=4)

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

                        # Determine contended status based on log messages
                        if route_name not in contended_status_map:
                            contended_status_map[route_name] = "-"
                        if "object is a candidate for contention" in msg_details or "updated route status" in msg_details:
                            contended_status_map[route_name] = "\033[93mCandidate\033[0m"
                        if "object has been modified by another writer" in msg_details:
                            contended_status_map[route_name] = "\033[91mContended\033[0m"
                            contentions += 1
                        if "object is contended and has been modified by another writer" in msg_details:
                            contentions += 1

                        contended_status = contended_status_map.get(route_name, "N/A")
                        if "reached max contentions" in msg_details:
                            max_contended = True

                        if max_contended:
                            contended_status = "\033[91mMaxContend\033[0m"

                        action_details = action_details.replace("UnservableInFutureVersions", "UIFV")
                        msg_details = msg_details.replace("skipped update due to another process altering the route with a different ingress status value", "skipped update another process altering the route")
                        
                        row = [len(all_logs) + 1, timestamp, route_name, contended_status, contentions, display_lease_state, action_details, msg_details]
                        if len(file_paths) > 1:
                            row.insert(2, f"{color_map[get_router_name(file_path)]}{get_router_name(file_path)}\033[0m")  # Append color code
                        previous_lease_state = lease_state  # Update the previous state
                        all_logs.append(row)
    
    # Sort logs by timestamp
    all_logs.sort(key=lambda x: x[1])
    for log in all_logs:
        table.add_row(log)

    return table

# Parse logs and print the table
global_route_map = build_global_route_map(log_file_paths)
table = parse_logs(log_file_paths, global_route_map)
print(table)