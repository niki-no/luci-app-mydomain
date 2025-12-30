module("luci.controller.domain", package.seeall)

-- 导入子控制器
require "luci.controller.domain.domain"
require "luci.controller.domain.certificate"
require "luci.controller.domain.proxy"
require "luci.controller.domain.system"

function index()
    -- 主菜单入口
    entry({"admin", "services", "domain"}, alias("admin", "services", "domain", "domain"), _("Dynamic Domain"), 60)
    
    -- 动态域名管理子菜单
    entry({"admin", "services", "domain", "domain"}, call("action_domain_overview"), _("Dynamic DNS"), 10).leaf = true
    entry({"admin", "services", "domain", "domain", "edit"}, form("domain/domain"), nil).leaf = true
    entry({"admin", "services", "domain", "domain", "edit", ":id"}, form("domain/domain"), nil).leaf = true
    entry({"admin", "services", "domain", "domain", "overview"}, template("domain/domain_overview"), _("Domain Overview"), 11).leaf = true
    
    -- 反向代理子菜单
    entry({"admin", "services", "domain", "proxy"}, cbi("domain/proxy"), _("Reverse Proxy"), 20)
    entry({"admin", "services", "domain", "proxy", "edit"}, form("domain/proxy_detail"), _("Edit Proxy Rule"), 21).leaf = true
    entry({"admin", "services", "domain", "proxy", "edit", ":id"}, form("domain/proxy_detail"), _("Edit Proxy Rule"), 22).leaf = true
    
    -- 证书管理子菜单
    entry({"admin", "services", "domain", "cert"}, cbi("domain/cert"), _("Certificate Management"), 30)
    entry({"admin", "services", "domain", "cert", "edit"}, form("domain/cert_detail"), _("Edit Certificate"), 31).leaf = true
    entry({"admin", "services", "domain", "cert", "edit", ":id"}, form("domain/cert_detail"), _("Edit Certificate"), 32).leaf = true
    entry({"admin", "services", "domain", "cert", "status"}, template("domain/cert_status"), _("Certificate Status"), 33).leaf = true
    
    -- 日志查看子菜单
    entry({"admin", "services", "domain", "logs"}, template("domain/log_viewer"), _("Log Viewer"), 40).leaf = true
    
    -- AJAX API 入口点将在子控制器中定义
end

-- 域名概览页面
function action_domain_overview()
    local uci = require "luci.model.uci".cursor()
    local domains = {}
    
    -- 获取所有域名配置
    uci:foreach("domain", "domain", function(s)
        table.insert(domains, {
            id = s[".name"],
            name = s.name or s[".name"],
            domain = s.domain,
            subdomains = s.subdomains,
            service = s.service,
            enabled = s.enabled,
            ipv4_enabled = s.ipv4_enabled,
            ipv6_enabled = s.ipv6_enabled
        })
    end)
    
    -- 渲染概览页面
    luci.template.render("domain/domain_overview", {domains = domains})
end
