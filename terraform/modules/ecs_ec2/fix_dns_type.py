import re

with open("main.tf", "r") as f:
    content = f.read()

# Replace type = "A" with type = "SRV" in the service discovery blocks
# But only for those inside aws_service_discovery_service
content = re.sub(r'(resource "aws_service_discovery_service".*?type\s*=\s*)"A"', r'\1"SRV"', content, flags=re.DOTALL)

with open("main.tf", "w") as f:
    f.write(content)

