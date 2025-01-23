import subprocess
import re
from collections import defaultdict
import sys

def parse_clusterrole_output(clusterrole_output):
    """
    Parses the output of `oc describe clusterrole` and builds a dictionary of resources and their verbs.
    Args:
        clusterrole_output (str): Output of `oc describe clusterrole <role>`.
    Returns:
        dict: A dictionary where keys are resources and values are sets of verbs.
    """
    resource_permissions = defaultdict(set)

    # Extract lines under "PolicyRule" header
    lines = clusterrole_output.splitlines()
    policy_rule_start = False

    for line in lines:
        line = line.strip()
        if line.startswith("PolicyRule:"):
            policy_rule_start = True
            continue
        if policy_rule_start and line:
            match = re.match(r"(.*?)\s+\[.*?\]\s+\[.*?\]\s+\[(.*?)\]", line)
            if match:
                resource, verbs = match.groups()
                resource_permissions[resource.strip()].update(
                    verb.strip() for verb in verbs.split(",")
                )

    return resource_permissions


def match_wildcards(resource, resources_dict):
    """
    Handle wildcard matches for resource names.
    Args:
        resource (str): The resource name to match (supports `*` as wildcard).
        resources_dict (dict): Dictionary of all resources and their verbs.
    Returns:
        set: Combined set of verbs for all matching resources.
    """
    if "*" not in resource:
        return resources_dict.get(resource, set())

    pattern = re.compile(resource.replace("*", ".*"))
    matching_verbs = set()
    for res, verbs in resources_dict.items():
        if pattern.fullmatch(res):
            matching_verbs.update(verbs)

    return matching_verbs


def compare_clusterroles(role1, role2, role1_name, role2_name):
    """
    Compares two cluster roles and prints differences in resource permissions.
    Args:
        role1 (dict): Resource permissions for the first role.
        role2 (dict): Resource permissions for the second role.
    """
    all_resources = set(role1.keys()).union(set(role2.keys()))

    for resource in sorted(all_resources):
        verbs1 = match_wildcards(resource, role1)
        verbs2 = match_wildcards(resource, role2)

        if verbs1 != verbs2:
            print(f"{resource}")
            print(f"  {role1_name}: {', '.join(sorted(verbs1)) or 'None'}")
            print(f"  {role2_name}: {', '.join(sorted(verbs2)) or 'None'}")
            print()


def main():
    if len(sys.argv) != 3:
        print("Usage: python compare_clusterroles.py <role1> <role2>")
        sys.exit(1)

    role1_name = sys.argv[1]
    role2_name = sys.argv[2]

    # Get the output of `oc describe clusterrole` for both roles
    role1_output = subprocess.check_output(["oc", "describe", "clusterrole", role1_name], text=True)
    role2_output = subprocess.check_output(["oc", "describe", "clusterrole", role2_name], text=True)

    # Parse the outputs
    role1_permissions = parse_clusterrole_output(role1_output)
    role2_permissions = parse_clusterrole_output(role2_output)

    # Compare the roles and print differences
    compare_clusterroles(role1_permissions, role2_permissions, role1_name, role2_name)


if __name__ == "__main__":
    main()

