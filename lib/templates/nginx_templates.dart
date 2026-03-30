class NginxTemplates {
  /// On Linux: 127.0.0.1 (host network mode).
  /// On Windows/macOS: host.docker.internal (Docker Desktop VM).
  static String _proxyHost(bool useHostNetwork) =>
      useHostNetwork ? '127.0.0.1' : 'host.docker.internal';

  static String odooConf({
    required String domain,
    required int httpPort,
    required int longpollingPort,
    bool useHostNetwork = true,
  }) {
    final host = _proxyHost(useHostNetwork);
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
        proxy_pass http://$host:$httpPort;
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
        proxy_pass http://$host:$httpPort;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    }

    # Odoo Longpolling
    location /longpolling/ {
        proxy_pass http://$host:$longpollingPort;
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
    bool useHostNetwork = true,
  }) {
    final host = _proxyHost(useHostNetwork);
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
        proxy_pass http://$host:$port;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    }
}
''';
  }

  // ── Project structure templates ──

  static String nginxConf({
    required String certFile,
    required String certKeyFile,
  }) {
    return '''user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log notice;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;

    # SSL
    ssl_certificate     $certFile;
    ssl_certificate_key $certKeyFile;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Timeout & Buffer
    keepalive_timeout           86400s;
    proxy_connect_timeout       86400s;
    proxy_send_timeout          86400s;
    proxy_read_timeout          86400s;
    client_body_timeout         86400s;
    client_header_timeout       86400s;
    client_max_body_size        1024M;
    proxy_request_buffering     off;
    proxy_buffering             off;
    proxy_buffers               8 16k;
    proxy_buffer_size           8k;

    include /etc/nginx/conf.d/*.conf;
}
''';
  }

  static String dockerCompose({bool useHostNetwork = true}) {
    final networkConfig = useHostNetwork
        ? '    network_mode: "host"'
        : '    ports:\n      - "80:80"\n      - "443:443"';
    return '''services:
  nginx:
    image: nginx:stable-alpine
    container_name: nginx
$networkConfig
    volumes:
      - ./certs:/etc/nginx/certs:ro
      - ./conf.d:/etc/nginx/conf.d:ro
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    restart: unless-stopped
''';
  }
}
