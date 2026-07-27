#!/bin/bash
set -e

DOMAIN=${DOMAIN:-api.manychurch.com}
EMAIL=${EMAIL:-admin@manychurch.com}

# Update server_name in nginx.conf
sed -i "s/server_name api.manychurch.com;/server_name $DOMAIN;/g" /etc/nginx/nginx.conf

if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    echo "No certificates found. Getting new certificates for $DOMAIN..."
    # Start nginx temporarily
    nginx -g "daemon on;"
    
    # Run certbot to get certs and automatically configure nginx for SSL
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect || echo "Certbot failed, but continuing..."
    
    # Stop nginx
    nginx -s quit
    sleep 2
else
    echo "Certificates already exist. Attempting renewal and configuring nginx..."
    # If the container restarted, the nginx.conf is reset because it's baked into the image.
    # But the certificates are on EFS. We need certbot to re-apply the nginx config.
    nginx -g "daemon on;"
    certbot install --nginx -d "$DOMAIN" --cert-name "$DOMAIN" --redirect || true
    nginx -s quit
    sleep 2
fi

# Run cron in background for auto-renewal
# (Assuming alpine, crond is available)
echo "0 0,12 * * * root certbot renew --nginx -q" >> /etc/crontabs/root
crond -b -l 8

echo "Starting Nginx in foreground..."
exec nginx -g "daemon off;"
