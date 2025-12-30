# DOMAIN LuCI App Makefile
# Copyright (c) 2024 DOMAIN Maintainers
# Licensed under the Apache License 2.0

include $(TOPDIR)/rules.mk

LUCI_TITLE:=DOMAIN Management Interface
LUCI_DEPENDS:=+luci \
    +luci-compat \
    +luci-lib-jsonc \
    +luci-lib-nixio \
    +luci-mod-admin-full \
    +curl \
    +openssl-util \
    +ca-bundle \
    +ca-certificates \
    +libopenssl
LUCI_DEPENDS+=+@(PACKAGE_luci-app-domain:SQLITE_SUPPORT)+sqlite3-cli +libsqlite3 +libpthread +libstdcpp
LUCI_DEPENDS+=+@(PACKAGE_luci-app-domain:PROXY_SUPPORT)+haproxy
LUCI_DEPENDS+=+@(PACKAGE_luci-app-domain:CERT_SUPPORT)+acme-acmesh
LUCI_DEPENDS+=+@(PACKAGE_luci-app-domain:HEALTH_CHECK_SUPPORT)+netcat-openbsd
LUCI_PKGARCH:=all
PKG_VERSION:=1.0.0
PKG_RELEASE:=2

PKG_NAME:=luci-app-domain
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=DOMAIN Maintainers <maintainers@domain.org>
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-domain
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=DOMAIN Management Interface
  URL:=https://github.com/domain/luci-app-domain
  PKGARCH:=all
endef

define Package/luci-app-domain/config
config PACKAGE_luci-app-domain:SQLITE_SUPPORT
    bool "Enable SQLite support"
    default y
    help
      Enable SQLite database support for logging and statistics.

config PACKAGE_luci-app-domain:PROXY_SUPPORT
    bool "Enable reverse proxy support"
    default y
    help
      Enable reverse proxy management with HAProxy.

config PACKAGE_luci-app-domain:CERT_SUPPORT
    bool "Enable certificate management"
    default y
    help
      Enable ACME certificate management.

config PACKAGE_luci-app-domain:HEALTH_CHECK_SUPPORT
    bool "Enable backend health check"
    default y
    help
      Enable backend server health check functionality.
endef

define Package/luci-app-domain/description
  A comprehensive LuCI interface for DOMAIN (Domain, DNS, and Certificate Management)
  with proxy capabilities and advanced networking features.
endef

define Package/luci-app-domain/conffiles
/etc/config/domain
/etc/domain/
/usr/lib/domain/
endef

define Build/Configure
endef

define Build/Compile
	$(call Build/Compile/luci,i18n)
endef

define Package/luci-app-domain/install
	# LuCI application files
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci
	cp -pR ./luasrc/* $(1)/usr/lib/lua/luci/
	
	# Static web files
	$(INSTALL_DIR) $(1)/www/luci-static/resources/domain
	$(INSTALL_DATA) ./htdocs/css/domain.css $(1)/www/luci-static/resources/domain/
	$(INSTALL_DATA) ./htdocs/js/domain.js $(1)/www/luci-static/resources/domain/
	$(INSTALL_DATA) ./htdocs/js/domain-enhanced.js $(1)/www/luci-static/resources/domain/
	$(INSTALL_DATA) ./htdocs/js/domain-proxy-cert.js $(1)/www/luci-static/resources/domain/
	
	# Icons and images
	$(INSTALL_DIR) $(1)/www/luci-static/resources/icons/domain
	$(INSTALL_DATA) ./htdocs/icons/* $(1)/www/luci-static/resources/icons/domain/ 2>/dev/null || true
	
	# Configuration files
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/domain $(1)/etc/config/domain
	
	$(INSTALL_DIR) $(1)/etc/domain
	$(INSTALL_DIR) $(1)/etc/domain/certs
	$(INSTALL_DIR) $(1)/etc/domain/data
	$(INSTALL_DIR) $(1)/etc/domain/backup
	$(INSTALL_DIR) $(1)/etc/domain/templates
	$(INSTALL_DIR) $(1)/etc/domain/scripts
	
	# Init scripts
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/domain $(1)/etc/init.d/domain
	
	# Service management scripts
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./root/usr/sbin/domain-cli $(1)/usr/sbin/ 2>/dev/null || true
	$(INSTALL_BIN) ./root/usr/sbin/domain-cert $(1)/usr/sbin/ 2>/dev/null || true
	
	# Library files
	$(INSTALL_DIR) $(1)/usr/lib/domain
	$(INSTALL_BIN) ./root/usr/lib/ddns/update.sh $(1)/usr/lib/domain/update-ddns.sh
	$(INSTALL_BIN) ./root/usr/lib/domain/*.sh $(1)/usr/lib/domain/ 2>/dev/null || true
	$(INSTALL_BIN) ./root/usr/lib/domain/*.lua $(1)/usr/lib/domain/ 2>/dev/null || true
	
	# Template files
	$(INSTALL_DIR) $(1)/usr/share/domain/templates
	$(INSTALL_DATA) ./root/usr/share/domain/templates/* $(1)/usr/share/domain/templates/ 2>/dev/null || true
	
	# Documentation
	$(INSTALL_DIR) $(1)/usr/share/doc/domain
	$(INSTALL_DATA) ./docs/* $(1)/usr/share/doc/domain/ 2>/dev/null || true
	
	# Create symlinks for LuCI
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-domain.json $(1)/usr/share/luci/menu.d/
	
	# Set permissions
	chmod 755 $(1)/etc/init.d/domain
	chmod 755 $(1)/usr/lib/domain/*.sh 2>/dev/null || true
	chmod 644 $(1)/etc/config/domain
endef

define Package/luci-app-domain/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	# Check if DOMAIN service exists
	if [ ! -f /usr/sbin/domain ]; then
		echo "Warning: DOMAIN service binary not found."
		echo "Please install the 'domain' package for full functionality."
	fi
	
	# Create service user if not exists and tools are available
	if command -v useradd >/dev/null 2>&1 && command -v groupadd >/dev/null 2>&1; then
	    if ! id "domain" >/dev/null 2>&1; then
	        echo "Creating service user 'domain'..."
	        useradd -r -s /bin/false -d /var/run/domain "domain" || true
	        groupadd -r "domain" 2>/dev/null || true
	        usermod -a -G "domain" "domain" 2>/dev/null || true
	    fi
	fi
	
	# Create data directories with correct permissions
	mkdir -p /etc/domain
	mkdir -p /etc/domain/certs
	mkdir -p /etc/domain/data
	mkdir -p /etc/domain/backup
	mkdir -p /etc/domain/logs
	mkdir -p /etc/domain/tmp
	
	chown -R domain:domain /etc/domain 2>/dev/null || true
	chmod 750 /etc/domain
	chmod 750 /etc/domain/certs
	chmod 750 /etc/domain/data
	chmod 750 /etc/domain/backup
	
	# Initialize configuration if not exists
	if [ ! -s /etc/config/domain ]; then
		echo "Initializing DOMAIN configuration..."
		cp /rom/etc/config/domain /etc/config/domain 2>/dev/null || \
		uci import domain < /dev/null
		
		# Set default values
		uci set domain.global.enabled=1
		uci set domain.global.version="1.0.0"
		uci set domain.global.data_dir="/etc/domain"
		uci commit domain
	fi
	
	# Enable service by default
	if [ -f /etc/init.d/domain ]; then
		/etc/init.d/domain enable
		
		# Check if service should be started
		if uci -q get domain.global.enabled | grep -q "1"; then
			echo "Starting DOMAIN service..."
			/etc/init.d/domain start || true
		fi
	fi
	
	# Update LuCI cache
	rm -f /tmp/luci-indexcache 2>/dev/null || true
	rm -f /tmp/luci-modulecache/* 2>/dev/null || true
	
	echo "DOMAIN LuCI app installed successfully."
	echo "Access it at: LuCI → Services → DOMAIN"
}
endef

define Package/luci-app-domain/prerm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	# Stop service before removal if running
	if [ -f /etc/init.d/domain ]; then
		/etc/init.d/domain stop 2>/dev/null || true
		/etc/init.d/domain disable 2>/dev/null || true
	fi
}
endef

define Package/luci-app-domain/postrm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	# Clean up LuCI cache
	rm -f /tmp/luci-indexcache 2>/dev/null || true
	rm -f /tmp/luci-modulecache/* 2>/dev/null || true
	
	# Remove empty directories
	rmdir /etc/domain/backup 2>/dev/null || true
	rmdir /etc/domain/data 2>/dev/null || true
	rmdir /etc/domain/certs 2>/dev/null || true
	rmdir /etc/domain 2>/dev/null || true
}
endef

$(eval $(call BuildPackage,luci-app-domain))