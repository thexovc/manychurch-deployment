import re

with open("outputs.tf", "r") as f:
    content = f.read()

content = re.sub(r'output\s+"ecs_service_aux_name"\s+\{[\s\S]*?\}', '', content)

with open("outputs.tf", "w") as f:
    f.write(content)

