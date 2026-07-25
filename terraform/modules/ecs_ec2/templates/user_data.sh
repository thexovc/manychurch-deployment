#!/bin/bash
# Enable 2GB Swap Memory to prevent OOM crashes on database and application containers
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Configure ECS Agent to register this instance to our ManyChurch cluster
echo "ECS_CLUSTER=${cluster_name}" >> /etc/ecs/ecs.config
echo "ECS_INSTANCE_ATTRIBUTES={\"role\":\"${instance_role}\",\"host_index\":\"${host_index}\"}" >> /etc/ecs/ecs.config
echo "ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true" >> /etc/ecs/ecs.config
echo "ECS_ENABLE_TASK_IAM_ROLE=true" >> /etc/ecs/ecs.config
echo "ECS_AVAILABLE_LOGGING_DRIVERS=[\"json-file\",\"awslogs\",\"none\"]" >> /etc/ecs/ecs.config

# Start/Restart ECS Agent
systemctl enable --now ecs
systemctl restart ecs
