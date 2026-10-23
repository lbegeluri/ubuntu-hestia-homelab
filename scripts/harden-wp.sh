#!/usr/bin/env bash
# WordPress hardening for a Hestia WordPress site (WEB_USER=… DOMAIN=… sudo -E bash harden-wp.sh). Run: sudo bash ~/harden-wp.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo bash "$0" "$@"

U=${WEB_USER:-webuser}; DOM=${DOMAIN:-wordpress.example.com}
ROOT=/home/$U/web/$DOM/public_html
CONF=/home/$U/conf/web/$DOM
MU=$ROOT/wp-content/mu-plugins
LAN=$(hostname -I | awk '{print $1}')

[ -f "$ROOT/wp-config.php" ] || { echo "WordPress not found in $ROOT - install it first"; exit 1; }
[ -d "$CONF" ] || { echo "Hestia conf dir $CONF missing"; exit 1; }

echo "== 1. mu-plugin: no user enumeration, no generator tag, no xmlrpc"
install -d -o $U -g $U -m 755 "$MU"
cat > "$MU/site-hardening.php" <<'PHP'
<?php
/* webuser hardening (must-use plugin) */

// REST API: hide /wp/v2/users for visitors who are not logged in
add_filter('rest_endpoints', function ($endpoints) {
    if (!is_user_logged_in()) {
        foreach (array_keys($endpoints) as $route) {
            if (preg_match('#^/wp/v2/users(/|$)#', $route)) {
                unset($endpoints[$route]);
            }
        }
    }
    return $endpoints;
});

// Author archives and /?author=N -> homepage (priority 0 = before WordPress canonical redirect leaks the slug)
add_action('template_redirect', function () {
    if (is_author() || isset($_GET['author'])) {
        wp_safe_redirect(home_url('/'), 301);
        exit;
    }
}, 0);

// Version disclosure + XML-RPC off
remove_action('wp_head', 'wp_generator');
add_filter('the_generator', '__return_empty_string');
add_filter('xmlrpc_enabled', '__return_false');
PHP
chown $U:$U "$MU/site-hardening.php"; chmod 644 "$MU/site-hardening.php"

echo "== 2. nginx: block readme/license/xmlrpc at the origin too"
cat > "$CONF/nginx.ssl.conf_hardening" <<'NG'
location = /readme.html  { return 404; }
location = /license.txt  { return 404; }
location = /xmlrpc.php   { return 403; }
NG
chmod 644 "$CONF/nginx.ssl.conf_hardening"
if nginx -t 2>/dev/null; then systemctl reload nginx && echo "nginx reloaded"; else
  echo "!! nginx -t failed - removing my include"; rm -f "$CONF/nginx.ssl.conf_hardening"; nginx -t; exit 1; fi

echo "== 3. verify (direct to origin via $LAN)"
R="--resolve $DOM:443:$LAN"
printf "wp-json users      : "; curl -sk $R -o /dev/null -w "%{http_code}  (want 401/404)\n" https://$DOM/wp-json/wp/v2/users
printf "users/1            : "; curl -sk $R -o /dev/null -w "%{http_code}  (want 401/404)\n" https://$DOM/wp-json/wp/v2/users/1
printf "?author=1          : "; curl -skI $R https://$DOM/?author=1 | awk 'NR==1{printf "%s ",$2} tolower($1)=="location:"{print $2}'
printf "readme.html        : "; curl -sk $R -o /dev/null -w "%{http_code}  (want 404)\n" https://$DOM/readme.html
printf "xmlrpc.php         : "; curl -sk $R -o /dev/null -w "%{http_code}  (want 403)\n" https://$DOM/xmlrpc.php
printf "generator tag      : "; curl -sk $R https://$DOM/ | grep -ci 'name="generator"' | sed 's/$/ matches (want 0)/'
printf "site still loads   : "; curl -sk $R -o /dev/null -w "%{http_code}  (want 200)\n" https://$DOM/
printf "wp-login still ok  : "; curl -sk $R -o /dev/null -w "%{http_code}  (want 200)\n" https://$DOM/wp-login.php
echo "undo: rm $MU/site-hardening.php $CONF/nginx.ssl.conf_hardening && systemctl reload nginx"
