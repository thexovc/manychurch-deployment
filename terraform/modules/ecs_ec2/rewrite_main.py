import re

with open("main.tf", "r") as f:
    lines = f.readlines()

def remove_resource(lines, resource_type, resource_name):
    start_idx = -1
    for i, line in enumerate(lines):
        if re.match(r'^resource\s+"' + resource_type + r'"\s+"' + resource_name + r'"\s+\{', line):
            start_idx = i
            break
    
    if start_idx == -1:
        return lines
        
    # Count braces to find the end
    brace_count = 0
    end_idx = -1
    for i in range(start_idx, len(lines)):
        brace_count += lines[i].count('{')
        brace_count -= lines[i].count('}')
        if brace_count == 0:
            end_idx = i
            break
            
    if end_idx != -1:
        # Also remove preceding comments
        while start_idx > 0 and (lines[start_idx-1].strip().startswith('#') or lines[start_idx-1].strip() == ''):
            start_idx -= 1
        return lines[:start_idx] + lines[end_idx+1:]
    return lines

to_remove = [
    ("aws_ecs_task_definition", "rabbitmq_notification"),
    ("aws_ecs_task_definition", "course_giving"),
    ("aws_ecs_task_definition", "wallet_support"),
    ("aws_ecs_task_definition", "admin_prometheus"),
    ("aws_ecs_task_definition", "grafana"),
    ("aws_service_discovery_service", "rabbitmq"),
    ("aws_service_discovery_service", "notification"),
    ("aws_ecs_service", "rabbitmq"),
    ("aws_ecs_service", "notification"),
    ("aws_ecs_service", "course_giving"),
    ("aws_ecs_service", "wallet_support"),
    ("aws_ecs_service", "admin_prometheus"),
    ("aws_ecs_service", "grafana"),
]

for res_type, res_name in to_remove:
    lines = remove_resource(lines, res_type, res_name)

content = "".join(lines)

# Remove NOTIFICATION_SERVICE_ADDR
content = re.sub(r'\s*\{\s*name\s*=\s*"NOTIFICATION_SERVICE_ADDR".*?\},?', '', content)

# Change host_index == 3 to host_index == 2
content = content.replace('attribute:host_index == 3', 'attribute:host_index == 2')

# Downsize ASG to 3
content = re.sub(r'(min_size\s*=\s*)4', r'\g<1>3', content)
content = re.sub(r'(max_size\s*=\s*)4', r'\g<1>3', content)
content = re.sub(r'(desired_capacity\s*=\s*)4', r'\g<1>3', content)

with open("main.tf", "w") as f:
    f.write(content)

