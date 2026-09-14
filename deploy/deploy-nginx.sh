#!/usr/bin/env bash
# Deploy the chatstub Flutter web app under nginx at https://<host>/app/.
# Run ON the server (Ubuntu 24.04 / nginx), as root.
#
#   bash deploy-nginx.sh [/tmp/chatstub-web.tar.gz] [/var/www/chatstub] [/app]
#
# Extracts the build to APPDIR, ensures an nginx `location /app/` (SPA
# fallback + wasm MIME) exists in the bizprozmco.com server block, tests
# the config, and reloads nginx. The app must have been built with
# --base-href /app/.
set -euo pipefail

TARBALL="${1:-/tmp/chatstub-web.tar.gz}"
APPDIR="${2:-/var/www/chatstub}"
BASEPATH="${3:-/app}"          # URL prefix, no trailing slash
SITE="/etc/nginx/sites-enabled/browser-phone"
STAMP="$(date +%Y%m%d-%H%M%S)"

[ -f "$TARBALL" ] || { echo "ERROR: tarball not found: $TARBALL" >&2; exit 1; }
[ -f "$SITE" ]    || { echo "ERROR: nginx site not found: $SITE" >&2; exit 1; }

echo "==> Installing build into ${APPDIR}"
mkdir -p "$APPDIR"
find "$APPDIR" -mindepth 1 -delete
tar -xzf "$TARBALL" -C "$APPDIR"
chown -R www-data:www-data "$APPDIR"
find "$APPDIR" -type d -exec chmod 755 {} \;
find "$APPDIR" -type f -exec chmod 644 {} \;

if grep -q "location ${BASEPATH}/" "$SITE"; then
  echo "==> nginx location ${BASEPATH}/ already present; leaving as-is"
else
  echo "==> Backing up ${SITE} -> ${SITE}.bak.${STAMP}"
  cp -a "$SITE" "${SITE}.bak.${STAMP}"

  echo "==> Inserting location ${BASEPATH}/ into the 443 server block"
  # Insert our block right after the first `root ` directive inside the
  # SSL (443) server. Uses awk to target the block that listens on 443.
  awk -v base="$BASEPATH" -v appdir="$APPDIR" '
    /listen 443/ { in443=1 }
    { print }
    in443 && /root[ \t]/ && !done {
      print "";
      print "    location " base "/ {";
      print "        alias " appdir "/;";
      print "        include /etc/nginx/mime.types;";
      print "        try_files $uri $uri/ " base "/index.html;";
      print "        add_header Cache-Control \"no-cache\" always;";
      print "    }";
      done=1;
    }
  ' "$SITE" > "${SITE}.new"
  mv "${SITE}.new" "$SITE"
fi

echo "==> Testing nginx config"
nginx -t

echo "==> Reloading nginx"
systemctl reload nginx

echo ""
echo "==> Done. Test: https://bizprozmco.com${BASEPATH}/"
echo "Rollback config: cp -a ${SITE}.bak.${STAMP} ${SITE} && systemctl reload nginx"
