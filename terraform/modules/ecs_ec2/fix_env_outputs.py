import re
import os

for env in ["dev", "prod"]:
    path = f"../environments/{env}/main.tf"
    if os.path.exists(path):
        with open(path, "r") as f:
            content = f.read()
            
        content = re.sub(r'output\s+"ecs_service_aux_name"\s+\{[\s\S]*?\}', '', content)
        
        with open(path, "w") as f:
            f.write(content)

