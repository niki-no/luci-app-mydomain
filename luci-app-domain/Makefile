# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2021-2025  sirpdboy  <herboy2008@gmail.com> 
# https://github.com/sirpdboy/luci-app-domain 
# This is free software, licensed under the Apache License, Version 2.0 .
#
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-domain
PKG_VERSION:=1.0.0
PKG_RELEASE:=20251228

PKG_MAINTAINER:=sirpdboy  <herboy2008@gmail.com>
PKG_CONFIG_DEPENDS:=

LUCI_TITLE:=LuCI Support for Domain Management
LUCI_DEPENDS:=+ddns-go +haproxy +acme
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/domain
/etc/config/ddns-go
/etc/config/haproxy
/etc/config/acme
/etc/ddns-go/ddns-go-config.yaml
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature