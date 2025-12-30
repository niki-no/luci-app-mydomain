local m, s, o
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

-- 
local config_id = arg[1]

m = Map("domain", translate("Reverse Proxy Configuration"),
    translate("Configure detailed settings for reverse proxy rules."))

m.redirect = luci.dispatcher.build_url("admin/services/domain/proxy")

-- 添加CSS加载模板
m:append(Template("domain/css_loader"))

if config_id then
    m.title = translate("Edit Proxy Rule")
else
    m.title = translate("Add Proxy Rule")
    config_id = luci.util.genid()
end

-- 创建代理规则配置部分
s = m:section(NamedSection, config_id, "proxy", translate("Basic Settings"))
s.anonymous = false
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable"))
o.default = "1"

o = s:option(Value, "name", translate("Rule Name"))
o.rmempty = false
o.datatype = "string"

-- 创建监听设置选项卡
s:tab("listen", translate("Listen Settings"))

o = s:taboption("listen", Value, "listen_address", translate("Listen Address"))
o.datatype = "ipaddr"
o.placeholder = "0.0.0.0"
o:value("0.0.0.0", translate("All IPv4 Addresses"))
o:value("::", translate("All IPv6 Addresses"))
o:value("127.0.0.1", "localhost")
o.default = "0.0.0.0"

o = s:taboption("listen", Value, "listen_port", translate("Listen Port"))
o.datatype = "port"
o.rmempty = false
o.default = "80"

o = s:taboption("listen", Flag, "ssl", translate("Enable SSL/TLS"))
o.default = "0"

o = s:taboption("listen", ListValue, "ssl_cert", translate("SSL Certificate"))
o:depends("ssl", "1")
o:value("", translate("-- Select Certificate --"))

o = s:taboption("listen", Flag, "ssl_redirect", translate("HTTP to HTTPS Redirect"))
o:depends("ssl", "1")
o.default = "1"

o = s:taboption("listen", Value, "ssl_redirect_port", translate("HTTP Redirect Port"))
o:depends("ssl_redirect", "1")
o.datatype = "port"
o.default = "80"

-- 创建前端设置选项卡
s:tab("frontend", translate("Frontend Settings"))

o = s:taboption("frontend", Value, "frontend_name", translate("Frontend Name"))
o.datatype = "string"
o.rmempty = false
o.placeholder = "https_in"
o.default = "https_in"

o = s:taboption("frontend", Value, "frontend_domain", translate("Frontend Domain"))
o.datatype = "hostname"
o.rmempty = false
o.placeholder = "example.com"

o = s:taboption("frontend", Value, "frontend_path", translate("URL Path"))
o.placeholder = "/"
o:value("/", translate("Root Path"))
o:value("/api/", "API Path")
o:value("/static/", "Static Files")
o.default = "/"

o = s:taboption("frontend", ListValue, "domain_match", translate("Domain Matching Mode"))
o:value("exact", translate("Exact Match"))
o:value("wildcard", translate("Wildcard Match"))
o:value("regex", translate("Regular Expression"))
o.default = "exact"

o = s:taboption("frontend", DynamicList, "frontend_acl", translate("ACL Rules"))
o.placeholder = "acl is_mv hdr(host) -i mv.movie.top"
o.description = translate("Enter ACL rules in HAProxy syntax, e.g: acl is_mv hdr(host) -i mv.movie.top")

o = s:taboption("frontend", DynamicList, "frontend_use_backend", translate("Use Backend Rules"))
o.placeholder = "use_backend backend_mv if is_mv"
o.description = translate("Enter backend selection rules in HAProxy syntax, e.g: use_backend backend_mv if is_mv")

-- 创建后端设置选项卡
s:tab("backend", translate("Backend Settings"))

o = s:taboption("backend", Value, "backend_name", translate("Backend Name"))
o.datatype = "string"
o.rmempty = false
o.placeholder = "backend_mv"
o.default = "backend_mv"

o = s:taboption("backend", DynamicList, "backend_servers", translate("Backend Servers"))
o.placeholder = "server server1 192.168.1.100:8080 check"
o.description = translate("Enter backend servers in HAProxy syntax, e.g: server server1 192.168.1.100:8080 check")

o = s:taboption("backend", ListValue, "backend_protocol", translate("Backend Protocol"))
o:value("http", "HTTP")
o:value("https", "HTTPS")
o:value("tcp", "TCP")
o:value("udp", "UDP")
o.default = "http"

o = s:taboption("backend", Value, "backend_balance", translate("Load Balancing Algorithm"))
o.placeholder = "roundrobin"
o:value("roundrobin", "Round Robin")
o:value("static-rr", "Static Round Robin")
o:value("leastconn", "Least Connections")
o:value("first", "First Available")
o:value("source", "Source IP Hash")
o:value("uri", "URI Hash")
o.default = "roundrobin"

-- 创建高级负载均衡选项卡
s:tab("loadbalance", translate("Advanced Load Balancing"))

-- 创建健康检查开关
o = s:taboption("loadbalance", Flag, "health_check", translate("Enable Health Check"))
o.default = "1"

o = s:taboption("loadbalance", Value, "check_interval", translate("Check Interval (ms)"))
o:depends("health_check", "1")
o.default = "2000"
o.datatype = "uinteger"

o = s:taboption("loadbalance", Value, "check_path", translate("Health Check Path"))
o:depends("health_check", "1")
o.default = "/"
o:value("/", translate("Root"))
o:value("/health", "Health Endpoint")
o:value("/ping", "Ping Endpoint")

o = s:taboption("loadbalance", Value, "maxconn", translate("Maximum Connections per Server"))
o.placeholder = "2000"
o.datatype = "uinteger"

o = s:taboption("loadbalance", Value, "connection_timeout", translate("Connection Timeout (ms)"))
o.placeholder = "5000"
o.datatype = "uinteger"

o = s:taboption("loadbalance", Value, "queue_timeout", translate("Queue Timeout (ms)"))
o.placeholder = "3000"
o.datatype = "uinteger"

-- 创建高级设置选项卡
s:tab("advanced", translate("Advanced Settings"))

o = s:taboption("advanced", Value, "max_connections", translate("Maximum Connections"))
o.default = "2000"
o.datatype = "uinteger"

o = s:taboption("advanced", Value, "timeout_connect", translate("Connection Timeout (ms)"))
o.default = "5000"
o.datatype = "uinteger"

o = s:taboption("advanced", Value, "timeout_server", translate("Server Timeout (ms)"))
o.default = "30000"
o.datatype = "uinteger"

o = s:taboption("advanced", Value, "timeout_client", translate("Client Timeout (ms)"))
o.default = "60000"
o.datatype = "uinteger"

o = s:taboption("advanced", Flag, "compression", translate("Enable Compression"))
o.default = "1"

o = s:taboption("advanced", ListValue, "compression_type", translate("Compression Type"))
o:depends("compression", "1")
o:value("gzip", "Gzip")
o:value("deflate", "Deflate")
o.default = "gzip"

o = s:taboption("advanced", Flag, "websocket", translate("WebSocket Support"))
o.default = "1"

-- 创建访问控制选项卡
s:tab("access", translate("Access Control"))

o = s:taboption("access", DynamicList, "allowed_ips", translate("Allowed IP Addresses"))
o.placeholder = "192.168.1.0/24"
o.datatype = "ipaddr"

o = s:taboption("access", DynamicList, "denied_ips", translate("Denied IP Addresses"))
o.placeholder = "10.0.0.0/8"
o.datatype = "ipaddr"

o = s:taboption("access", Flag, "rate_limit", translate("Enable Rate Limiting"))
o.default = "0"

o = s:taboption("access", Value, "rate_limit_count", translate("Requests per Second"))
o:depends("rate_limit", "1")
o.default = "100"
o.datatype = "uinteger"

-- 创建日志设置选项卡
s:tab("logging", translate("Logging Settings"))

o = s:taboption("logging", Flag, "log_enabled", translate("Enable Logging"))
o.default = "1"

o = s:taboption("logging", ListValue, "log_level", translate("Log Level"))
o:depends("log_enabled", "1")
o:value("emerg", "Emergency")
o:value("alert", "Alert")
o:value("crit", "Critical")
o:value("err", "Error")
o:value("warning", "Warning")
o:value("notice", "Notice")
o:value("info", "Info")
o:value("debug", "Debug")
o.default = "info"

o = s:taboption("logging", Value, "log_format", translate("Log Format"))
o:depends("log_enabled", "1")
o.default = "%t %h %r %s %b"
o.placeholder = "HAProxy default format"

-- 创建状态和测试选项卡
s:tab("status", translate("Status & Testing"))

o = s:taboption("status", DummyValue, "_status", translate("Configuration Status"))
function o.cfgvalue(self, section)
    local enabled = m:get(section, "enabled") or "1"
    local domain = m:get(section, "frontend_domain") or ""
    local backend = m:get(section, "backend_ip") or ""
    local port = m:get(section, "backend_port") or ""
    
    local status = ""
    if enabled == "1" then
        status = '<span class="status-success">已启用</span>'
    else
        status = '<span class="status-pending">已禁用</span>'
    end
    
    if domain and backend and port then
        status = status .. '<br>' .. translate("Rule: ") .. domain .. ' → ' .. backend .. ':' .. port
    end
    
    return status
end
o.rawhtml = true

o = s:taboption("status", Button, "_test_backend", translate("Test Backend Connection"))
o.inputtitle = translate("Test Connection")
o.inputstyle = "apply"
function o.write(self, section, value)
    local backend = m:get(section, "backend_ip")
    local port = m:get(section, "backend_port")
    
    if backend and port then
        local cmd = string.format("nc -zv -w 2 %s %s 2>&1", backend, port)
        local result = sys.exec(cmd)
        
        if result:match("succeeded") then
            luci.http.redirect(luci.dispatcher.build_url("admin", "services", "domain", "proxy", "test_result", "success"))
        else
            luci.http.redirect(luci.dispatcher.build_url("admin", "services", "domain", "proxy", "test_result", "failed"))
        end
    end
end

-- 创建立即应用配置按钮
o = s:taboption("status", Button, "_apply_now", translate("Apply Configuration Now"))
o.inputtitle = translate("Apply Now")
o.inputstyle = "apply"
function o.write(self, section, value)
    -- 导入nixio库
    local nixio = require "nixio"
    local args = {"/etc/init.d/haproxy", "restart"}
    local pid = nixio.fork()
    
    if pid == 0 then
        nixio.chdir("/")
        nixio.dup(nixio.open("/dev/null", "w")), nixio.stderr)
        nixio.dup(nixio.open("/dev/null", "w")), nixio.stdout)
        nixio.exec(unpack(args))
        os.exit(1)
    end
    
    luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/proxy"))
end

return m
