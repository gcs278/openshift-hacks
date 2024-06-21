#!/usr/bin/env python3
import os
import re
import sys

def split_logs(input_file, output_dir):
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)  # Create the directory if it does not exist
    
    current_file = None
    current_pod_name = None
    
    with open(input_file, 'r') as file:
        for line in file:
            start_match = re.search(r'Log for pod "(.*)"/"router"', line)
            end_match = re.search(r'<----end of log for "(.*)"/"router"', line)
            
            if start_match:
                # Close the current file if it's open
                if current_file:
                    current_file.close()
                    current_file = None
                
                # Extract pod name and create a new file
                pod_name = start_match.group(1)
                current_pod_name = pod_name  # Keep track of the current pod name
                current_file = open(os.path.join(output_dir, f"{pod_name}.log"), 'w')
            
            elif end_match:
                # Check if the end log corresponds to the current pod
                if current_pod_name == end_match.group(1) and current_file:
                    print(f"finished writing {current_file}")
                    current_file.close()
                    current_file = None
                    current_pod_name = None

            # Write to the current log file if it's open
            if current_file:
                current_file.write(line)

    # Ensure the last file is closed properly
    if current_file:
        current_file.close()

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python script.py <path_to_log_file> <output_directory>")
        sys.exit(1)

    log_file_path = sys.argv[1]
    output_directory = sys.argv[2]

    # Run the function with the provided arguments
    split_logs(log_file_path, output_directory)
