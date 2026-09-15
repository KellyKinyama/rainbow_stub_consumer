#!/usr/bin/env bash
# Deploy the chatstub Flutter web app to the Apache document root.
# Run ON the server (bizprozmco.com), with sudo/root.
#
#   sudo bash deploy.sh [/path/to/chatstub-web.tar.gz] [/var/www/html]
#
# It backs up the current docroot, replaces it with the new build, writes
# an .htaccess for SPA deep-link fallback + wasm MIME, fixes ownership,
# restores SELinux context (RHEL/OL), and reloads Apache.
set -euo pipefail

TARBALL="${1:-/tmp/chatstub-web.tar.gz}"
DOCROOT="${2:-/var/www/html}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${DOCROOT}.bak.${STAMP}"

[ -f "$TARBALL" ] || { echo "ERROR: tarball not found: $TARBALL" >&2; exit 1; }

echo "==> Backing up ${DOCROOT} -> ${BACKUP}"
if [ -d "$DOCROOT" ] && [ -n "$(ls -A "$DOCROOT" 2>/dev/null)" ]; then
  cp -a "$DOCROOT" "$BACKUP"
fi

echo "==> Replacing docroot contents from ${TARBALL}"
mkdir -p "$DOCROOT"
find "$DOCROOT" -mindepth 1 -delete
tar -xzf "$TARBALL" -C "$DOCROOT"

echo "==> Writing .htaccess (SPA fallback + wasm MIME)"
cat > "${DOCROOT}/.htaccess" <<'HT'
AddType application/wasm .wasm
<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteBase /
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteRule ^ index.html [L]
</IfModule>
HT

echo "==> Fixing ownership + permissions"
if id apache >/dev/null 2>&1; then OWN=apache; else OWN=www-data; fi
chown -R "${OWN}:${OWN}" "$DOCROOT"
find "$DOCROOT" -type d -exec chmod 755 {} \;
find "$DOCROOT" -type f -exec chmod 644 {} \;

if command -v restorecon >/dev/null 2>&1; then
  echo "==> restorecon (SELinux)"
  restorecon -R "$DOCROOT" || true
fi

# Configure Apache. Prefer a server-managed conf (no reliance on .htaccess /
# AllowOverride) so SPA deep-links + wasm MIME work out of the box.
if command -v a2enmod >/dev/null 2>&1; then
  echo "==> Ubuntu/Debian Apache: enabling mod_rewrite + directory conf"
  a2enmod rewrite >/dev/null 2>&1 || true
  cat > /etc/apache2/conf-available/chatstub.conf <<CONF
<Directory "${DOCROOT}">
    Options -Indexes +FollowSymLinks
    AllowOverride None
    Require all granted
    AddType application/wasm .wasm
    RewriteEngine On
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule ^ /index.html [L]
</Directory>
CONF
  a2enconf chatstub >/dev/null 2>&1 || true
  APACHE_SVC=apache2
elif [ -d /etc/httpd/conf.d ]; then
  echo "==> RHEL/OL Apache: installing directory conf"
  cat > /etc/httpd/conf.d/chatstub.conf <<CONF
<Directory "${DOCROOT}">
    Options -Indexes +FollowSymLinks
    AllowOverride None
    Require all granted
    AddType application/wasm .wasm
    RewriteEngine On
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule ^ /index.html [L]
</Directory>
CONF
  APACHE_SVC=httpd
else
  APACHE_SVC=apache2
fi

echo "==> Validating Apache config"
if command -v apachectl >/dev/null 2>&1; then apachectl configtest || true; fi

echo "==> Reloading Apache (${APACHE_SVC})"
systemctl reload "$APACHE_SVC" 2>/dev/null || systemctl restart "$APACHE_SVC" || \
  echo "!! reload Apache manually (systemctl reload ${APACHE_SVC})"

echo ""
echo "==> Done. Test: https://bizprozmco.com/"
echo "Rollback: rm -rf ${DOCROOT}/* && cp -a ${BACKUP}/. ${DOCROOT}/"
