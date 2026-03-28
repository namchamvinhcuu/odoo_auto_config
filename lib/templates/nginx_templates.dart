class NginxTemplates {
  static String odooConf({
    required String domain,
    required int httpPort,
    required int longpollingPort,
  }) {
    return '''# Redirect HTTP -> HTTPS
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

# HTTPS Server
server {
    listen 443 ssl;
    server_name $domain;

    access_log /var/log/nginx/$domain.access.log main;
    error_log /var/log/nginx/$domain.error.log;

    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;

    # WebSocket (Odoo 17+)
    location /websocket {
        proxy_pass http://127.0.0.1:$httpPort;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_connect_timeout 720s;
        proxy_buffering off;
    }

    # Odoo Web
    location / {
        proxy_pass http://127.0.0.1:$httpPort;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    }

    # Odoo Longpolling
    location /longpolling/ {
        proxy_pass http://127.0.0.1:$longpollingPort;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
''';
  }

  static String genericConf({
    required String domain,
    required int port,
  }) {
    return '''# Redirect HTTP -> HTTPS
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

# HTTPS Server
server {
    listen 443 ssl;
    server_name $domain;

    access_log /var/log/nginx/$domain.access.log main;
    error_log /var/log/nginx/$domain.error.log;

    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;

    location / {
        proxy_pass http://127.0.0.1:$port;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    }
}
''';
  }
}
