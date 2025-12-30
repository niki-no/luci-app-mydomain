local m, s, o
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

m = Map("domain", translate("Enhanced Dynamic DNS"),
    translate("Support multiple DNS providers, IPv4/IPv6 dual-stack, multiple domains, and real-time monitoring."))

-- 全局设置部分
s = m:section(NamedSection, "global", "ddns", translate("Global Settings"))
s.anonymous = true

o = s:option(Flag, "enabled", translate("Enable DDNS Service"))
o.default = "1"

o = s:option(ListValue, "log_level", translate("Log Level"))
o:value("debug", translate("Debug"))
o:value("info", translate("Info"))
o:value("error", translate("Error"))
o.default = "info"

o = s:option(Value, "log_file", translate("Log File Path"))
o.default = "/var/log/ddns.log"
o.datatype = "file"

-- 域名配置列表部分
s = m:section(TypedSection, "domain", translate("Domain Configurations"))
s.anonymous = false
s.addremove = true
s.template = "cbi/tblsection"
s.extedit = luci.dispatcher.build_url("admin/services/domain/domain/edit/%s")

function s.create(self, section)
    local sid = TypedSection.create(self, section)
    luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/domain/edit", sid))
end

-- DNS服务提供商选项
o = s:option(ListValue, "service", translate("Service Provider"))
o:value("dnspod", "DNSPod (腾讯云)")
o:value("aliyun", "Aliyun (阿里云)")
o:value("cloudflare", "Cloudflare")
o:value("huaweicloud", "Huawei Cloud")
o:value("godaddy", "GoDaddy")
o:value("dynu", "Dynu")
o:value("noip", "No-IP")
o:value("custom", translate("Custom API"))
o.width = "20%"

-- 创建启用开关
o = s:option(Flag, "enabled", translate("Enabled"))
o.width = "10%"

-- 创建域名显示
o = s:option(DummyValue, "main_domain", translate("Domain"))
function o.cfgvalue(self, section)
    local val = m:get(section, "domain")
    local sub = m:get(section, "subdomain")
    if sub and sub ~= "" then
        return sub .. "." .. (val or "")
    end
    return val or ""
end
o.width = "20%"

-- 创建IP类型显示
o = s:option(DummyValue, "ip_type", translate("IP Type"))
function o.cfgvalue(self, section)
    local ipv4 = m:get(section, "ipv4_enabled") or "0"
    local ipv6 = m:get(section, "ipv6_enabled") or "0"
    if ipv4 == "1" and ipv6 == "1" then
        return translate("IPv4/IPv6 Dual Stack")
    elseif ipv4 == "1" then
        return "IPv4"
    elseif ipv6 == "1" then
        return "IPv6"
    end
    return translate("Disabled")
end

-- 创建状态显示
o = s:option(DummyValue, "status", translate("Status"))
function o.cfgvalue(self, section)
    local status_file = "/tmp/ddns_" .. section .. ".status"
    local f = io.open(status_file, "r")
    if f then
        local content = f:read("*all")
        f:close()
        local status, ip, time = content:match("status:(%w+)%s+ip:(%S+)%s+time:(.+)")
        if status == "success" then
            return string.format('<span class="status-success">%s (%s)</span>', 
                translate("Updated"), time or "")
        elseif status == "failed" then
            return string.format('<span class="status-failed">%s</span>', 
                translate("Failed"))
        end
    end
    return '<span class="status-pending">' .. translate("Never updated") .. '</span>'
end
o.rawhtml = true
o.width = "30%"

-- 创建域名配置表单
m2 = Map("domain", translate("DDNS Domain Configuration"))

s2 = m2:section(NamedSection, arg[1], "domain", translate("Domain Settings"))
s2.anonymous = false
s2.addremove = false

-- 创建配置名称字段
o = s2:option(Value, "name", translate("Configuration Name"))
o.rmempty = false

-- 创建主域名字段
o = s2:option(Value, "domain", translate("Primary Domain"))
o.datatype = "hostname"
o.rmempty = false

-- 创建子域名列表
o = s2:option(DynamicList, "subdomains", translate("Subdomains"))
o.placeholder = "www"
o:value("@", translate("Root Domain (@)"))
o:value("*", translate("Wildcard (*)"))
o.default = "@"
o.datatype = "hostname"

-- DNS服务提供商选项
o = s2:option(ListValue, "service", translate("DNS Service Provider"))
o:value("dnspod", "DNSPod (腾讯云)")
o:value("aliyun", "Aliyun (阿里云)")
o:value("cloudflare", "Cloudflare")
o:value("huaweicloud", "Huawei Cloud")
o:value("godaddy", "GoDaddy")
o:value("dynu", "Dynu")
o:value("noip", "No-IP")
o:value("custom", translate("Custom API"))
o.rmempty = false

-- 创建API用户名/ID字段
o = s2:option(Value, "username", translate("API ID/Username"))
o:depends("service", "dnspod")
o:depends("service", "aliyun")
o:depends("service", "huaweicloud")
o:depends("service", "godaddy")
o:depends("service", "dynu")
o:depends("service", "noip")
o:depends("service", "custom")
o.rmempty = true
-- 验证用户名格式
function o.validate(self, value, section)
    if value and value:match("[<>&'\"\\]") then
        return nil, translate("Invalid characters in username")
    end
    return value
end

o = s2:option(Value, "password", translate("API Token/Password"))
o.password = true
o:depends("service", "dnspod")
o:depends("service", "aliyun")
o:depends("service", "cloudflare")
o:depends("service", "huaweicloud")
o:depends("service", "godaddy")
o:depends("service", "dynu")
o:depends("service", "noip")
o:depends("service", "custom")
o.rmempty = true
-- 验证密码/令牌格式
function o.validate(self, value, section)
    if value and not value:match("^[a-zA-Z0-9_%-%.@=%+/]+$") then
        return nil, translate("Invalid characters in password/token")
    end
    return value
end

-- 创建Cloudflare Zone ID字段
o = s2:option(Value, "zone_id", translate("Zone ID"))
o:depends("service", "cloudflare")
o.rmempty = true
-- 验证Cloudflare Zone ID格式
function o.validate(self, value, section)
    if value and not value:match("^[a-fA-F0-9]{32}$") then
        return nil, translate("Invalid Cloudflare Zone ID format")
    end
    return value
end

-- 创建自定义更新URL字段
o = s2:option(Value, "update_url", translate("Update URL"))
o:depends("service", "custom")
o.placeholder = "https://api.example.com/update?hostname={HOSTNAME}&ip={IP}"
o.datatype = "url"
o.rmempty = false

-- 验证URL格式
function o.validate(self, value, section)
    if value and not value:match("^https?://[^%s]+$") then
        return nil, translate("Invalid URL format")
    end
    return value
end

o = s2:option(Value, "update_method", translate("HTTP Method"))
o:depends("service", "custom")
o:value("GET", "GET")
o:value("POST", "POST")
o.default = "GET"
o.rmempty = false

-- 创建IP设置选项卡
s2:tab("ipv4", translate("IPv4 Settings"))
s2:tab("ipv6", translate("IPv6 Settings"))

-- 创建IPv4启用开关
o = s2:taboption("ipv4", Flag, "ipv4_enabled", translate("Enable IPv4 Update"))
o.default = "1"

o = s2:taboption("ipv4", ListValue, "ipv4_source", translate("IPv4 Source"))
o:value("interface", translate("Network Interface"))
o:value("web", translate("Web Service"))
o:value("script", translate("Custom Script"))
o:value("url", translate("Specific URL"))
o:depends("ipv4_enabled", "1")

o = s2:taboption("ipv4", ListValue, "ipv4_interface", translate("Network Interface"))
for _, iface in ipairs(sys.net.devices()) do
    if iface ~= "lo" then
        o:value(iface, iface)
    end
end
o:depends({ipv4_source = "interface", ipv4_enabled = "1"})

o = s2:taboption("ipv4", ListValue, "ipv4_webservice", translate("Web Service"))
o:value("myip.ipip.net", "myip.ipip.net")
o:value("ddns.oray.com", "ddns.oray.com")
o:value("ip.3322.net", "ip.3322.net")
o:value("4.ipw.cn", "4.ipw.cn")
o:value("v4.yinghualuo.cn", "v4.yinghualuo.cn")
o:depends({ipv4_source = "web", ipv4_enabled = "1"})

o = s2:taboption("ipv4", Value, "ipv4_url", translate("Custom URL"))
o:depends({ipv4_source = "url", ipv4_enabled = "1"})
o.placeholder = "http://api.ipify.org/"

o = s2:taboption("ipv4", Value, "ipv4_script", translate("Script Path"))
o:depends({ipv4_source = "script", ipv4_enabled = "1"})
o.datatype = "file"

-- 创建IPv6启用开关
o = s2:taboption("ipv6", Flag, "ipv6_enabled", translate("Enable IPv6 Update"))
o.default = "0"

o = s2:taboption("ipv6", ListValue, "ipv6_source", translate("IPv6 Source"))
o:value("interface", translate("Network Interface"))
o:value("web", translate("Web Service"))
o:value("script", translate("Custom Script"))
o:value("url", translate("Specific URL"))
o:depends("ipv6_enabled", "1")

o = s2:taboption("ipv6", ListValue, "ipv6_interface", translate("Network Interface"))
for _, iface in ipairs(sys.net.devices()) do
    if iface ~= "lo" then
        o:value(iface, iface)
    end
end
o:depends({ipv6_source = "interface", ipv6_enabled = "1"})

o = s2:taboption("ipv6", ListValue, "ipv6_webservice", translate("Web Service"))
o:value("speed.neu6.edu.cn", "speed.neu6.edu.cn")
o:value("v6.ident.me", "v6.ident.me")
o:value("6.ipw.cn", "6.ipw.cn")
o:value("v6.yinghualuo.cn", "v6.yinghualuo.cn")
o:depends({ipv6_source = "web", ipv6_enabled = "1"})

o = s2:taboption("ipv6", Value, "ipv6_url", translate("Custom URL"))
o:depends({ipv6_source = "url", ipv6_enabled = "1"})
o.placeholder = "http://api6.ipify.org/"

o = s2:taboption("ipv6", Value, "ipv6_script", translate("Script Path"))
o:depends({ipv6_source = "script", ipv6_enabled = "1"})
o.datatype = "file"

-- 创建更新设置选项卡
s2:tab("update", translate("Update Settings"))

o = s2:taboption("update", Value, "check_interval", translate("Check Interval (seconds)"))
o.default = "300"
o.datatype = "uinteger"
o:value("60", translate("1 minute"))
o:value("300", translate("5 minutes"))
o:value("600", translate("10 minutes"))
o:value("1800", translate("30 minutes"))
o:value("3600", translate("1 hour"))

o = s2:taboption("update", Flag, "force_update", translate("Force Update"))
o.default = "0"
o.description = translate("Force update even if IP hasn't changed")

o = s2:taboption("update", Value, "force_interval", translate("Force Update Interval (hours)"))
o.default = "168"
o.datatype = "uinteger"
o:value("24", translate("24 hours"))
o:value("168", translate("7 days"))
o:value("720", translate("30 days"))
o:depends("force_update", "1")

-- 创建高级设置选项卡
s2:tab("advanced", translate("Advanced Settings"))

o = s2:taboption("advanced", Value, "retry_count", translate("Retry Count"))
o.default = "3"
o.datatype = "uinteger"

o = s2:taboption("advanced", Value, "retry_interval", translate("Retry Interval (seconds)"))
o.default = "30"
o.datatype = "uinteger"

o = s2:taboption("advanced", Flag, "use_https", translate("Use HTTPS"))
o.default = "1"

o = s2:taboption("advanced", Value, "user_agent", translate("Custom User-Agent"))
o.placeholder = "Mozilla/5.0 (OpenWrt DDNS Client)"

-- 创建状态和日志选项卡
s2:tab("status", translate("Status & Logs"))

o = s2:taboption("status", DummyValue, "_status", translate("Current Status"))
function o.cfgvalue(self, section)
    local status_file = "/tmp/ddns_" .. section .. ".status"
    local f = io.open(status_file, "r")
    if f then
        local content = f:read("*all")
        f:close()
        return '<pre style="background:#f5f5f5;padding:10px;border-radius:3px">' .. 
               luci.util.pcdata(content) .. '</pre>'
    end
    return translate("No status information available")
end
o.rawhtml = true

o = s2:taboption("status", Button, "_view_log", translate("View Log"))
o.inputtitle = translate("View Full Log")
o.inputstyle = "apply"
function o.write(self, section, value)
    luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/logs"))
end

-- 创建立即更新按钮
o = s2:taboption("update", Button, "_force_update", translate("Force Update Now"))
o.inputtitle = translate("Update Immediately")
o.inputstyle = "apply"
function o.write(self, section, value)
    -- 验证section参数
    if not section or not section:match("^[a-zA-Z0-9_-]+$") then
        luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/domain/overview"))
        return
    end
    
    -- 导入nixio库
    local nixio = require "nixio"
    local args = {"/usr/lib/ddns/update.sh", section, "force"}
    local pid = nixio.fork()
    
    if pid == 0 then
        nixio.chdir("/")
        nixio.dup(nixio.open("/dev/null", "w")), nixio.stderr)
        nixio.dup(nixio.open("/dev/null", "w")), nixio.stdout)
        nixio.exec(unpack(args))
        os.exit(1)
    end
    
    luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/domain/overview"))
end

-- 
if arg[1] then
    return m2
else
    return m
end
