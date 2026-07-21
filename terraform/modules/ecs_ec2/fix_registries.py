import re

with open("main.tf", "r") as f:
    content = f.read()

def replacer(match):
    svc = match.group(1)
    
    ports = {
        "postgres": 5432,
        "rabbitmq": 5672,
        "auth": 50051,
        "church": 50052,
        "member": 50053,
        "notification": 50054
    }
    
    if svc in ports:
        return f"""  service_registries {{
    registry_arn   = aws_service_discovery_service.{svc}.arn
    container_name = "{svc}"
    container_port = {ports[svc]}
  }}"""
    return match.group(0)

# The regex matches the service_registries block
pattern = re.compile(r'  service_registries \{\n    registry_arn = aws_service_discovery_service\.(\w+)\.arn\n  \}')
content = pattern.sub(replacer, content)

with open("main.tf", "w") as f:
    f.write(content)

