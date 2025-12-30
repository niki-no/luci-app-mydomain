include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-domain
PKG_VERSION:=1.0.0
PKG_RELEASE:=2
PKG_MAINTAINER:=DOMAIN Maintainers <maintainers@domain.org>
PKG_LICENSE:=Apache-2.0

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
LUCI_DEPENDS+=+@PACKAGE_luci-app-domain_SQLITE_SUPPORT:sqlite3-cli +libsqlite3 +libpthread +libstdcpp
LUCI_DEPENDS+=+@PACKAGE_luci-app-domain_PROXY_SUPPORT:haproxy
LUCI_DEPENDS+=+@PACKAGE_luci-app-domain_CERT_SUPPORT:acme-acmesh
LUCI_DEPENDS+=+@PACKAGE_luci-app-domain_HEALTH_CHECK_SUPPORT:netcat-openbsd
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-domain/config
    config PACKAGE_luci-app-domain_SQLITE_SUPPORT
        bool "Enable SQLite support"
        default y

    config PACKAGE_luci-app-domain_PROXY_SUPPORT
        bool "Enable reverse proxy support"
        default y

    config PACKAGE_luci-app-domain_CERT_SUPPORT
        bool "Enable certificate management"
        default y

    config PACKAGE_luci-app-domain_HEALTH_CHECK_SUPPORT
        bool "Enable backend health check"
        default y
endef

define Package/luci-app-domain/install
	# 安装基础文件
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci
	cp -pR ./luasrc/* $(1)/usr/lib/lua/luci/
	
	# 静态资源
	$(INSTALL_DIR) $(1)/www/luci-static/resources/domain
	$(INSTALL_DATA) ./htdocs/*.css $(1)/www/luci-static/resources/domain/
	$(INSTALL_DATA) ./htdocs/*.js $(1)/www/luci-static/resources/domain/
	
	# 配置文件
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/domain $(1)/etc/config/
	
	# 初始化脚本
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/domain $(1)/etc/init.d/
	
	# 可执行文件
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/domain* $(1)/usr/bin/
	
	# 数据目录
	$(INSTALL_DIR) $(1)/etc/domain/{certs,data,backup,logs,tmp}
	
	# 设置权限
	find $(1)/etc/init.d -type f -exec chmod 755 {} \;
	find $(1)/usr/bin -type f -exec chmod 755 {} \;
	find $(1)/etc/config -type f -exec chmod 644 {} \;
	find $(1)/etc/domain -type d -exec chmod 750 {} \;
	chmod 700 $(1)/etc/domain/certs
endef

define Package/luci-app-domain/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	# 初始化配置
	if [ ! -s /etc/config/domain ]; then
		uci import domain < /dev/null
		uci set domain.global.enabled=1
		uci set domain.global.version="1.0.0"
		uci commit domain
	fi
	
	# 启用服务
	/etc/init.d/domain enable
	uci -q get domain.global.enabled | grep -q "1" && /etc/init.d/domain start
	
	# 清理缓存
	rm -f /tmp/luci-*cache* 2>/dev/null
	echo "DOMAIN LuCI app installed. Access at: LuCI → Services → DOMAIN"
}
exit 0
endef

define Package/luci-app-domain/prerm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/domain stop 2>/dev/null
	/etc/init.d/domain disable 2>/dev/null
}
endef

define Package/luci-app-domain/postrm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	rm -f /tmp/luci-*cache* 2>/dev/null
}
endef

$(eval $(call BuildPackage,luci-app-domain))
