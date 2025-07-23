#!/bin/bash

set -e

function generate_nginx_conf() {
  local L_CONF_PATH="${1}"
  local L_NODE_RPC_PORT="${2}"
  local L_NODE_REST_PORT="${3}"
  local L_NODE_GRPC_PORT="${4}"

  cat >"${L_CONF_PATH}" <<EOL
server {
    listen       ${L_NODE_REST_PORT};
    server_name  localhost;
    location / {
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            #
            # Custom headers and headers various browsers *should* be OK with but aren't
            #
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            #
            # Tell client that this pre-flight info is valid for 20 days
            #
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
        if (\$request_method = 'POST') {
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
        }
        if (\$request_method = 'GET') {
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
        }

        proxy_pass http://127.0.0.1:1317;
    }

}

server {
    listen       ${L_NODE_RPC_PORT};
    server_name  localhost;
    location / {
        proxy_pass http://127.0.0.1:26657;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        add_header "Access-Control-Allow-Origin"  "*";
        add_header "Access-Control-Allow-Methods" "GET, POST, OPTIONS, HEAD";
        add_header "Access-Control-Allow-Headers" "Authorization, Origin, X-Requested-With, Content-Type, Accept";
    }

    location /websocket {

        proxy_pass http://127.0.0.1:26657;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

    }


}

server {
    listen       ${L_NODE_GRPC_PORT} http2;
    server_name  localhost;
    location / {
        grpc_pass grpc://127.0.0.1:9090;
    }

}

EOL
}
