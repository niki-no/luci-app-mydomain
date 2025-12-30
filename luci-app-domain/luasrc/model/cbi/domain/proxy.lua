local m, s, o
local uci = require "luci.model.uci".cursor()

m = Map("domain", translate("Reverse Proxy Configuration"),
    translate("Configure reverse proxy rules using HAProxy."))

-- 添加CSS加载模板
m:append(Template("domain/css_loader"))

-- 创建全局设置部分
s = m:section(NamedSection, "global", "proxy", translate("Global Settings"))
s.anonymous = true

o = s:option(Value, "maxconn", translate("Maximum Connections"))
o.default = "2000"
o.datatype = "uinteger"

o = s:option(Flag, "log_enabled", translate("Enable Logging"))
o.default = "1"

o = s:option(ListValue, "log_level", translate("Log Level"))
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

-- 代理规则列表部分
s = m:section(TypedSection, "proxy", translate("Proxy Rules"))
s.anonymous = false
s.addremove = true
s.template = "cbi/tblsection"
s.extedit = luci.dispatcher.build_url("admin/services/domain/proxy/edit/%s")

function s.create(self, section)
    local sid = TypedSection.create(self, section)
    luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/proxy/edit", sid))
end

-- 规则名称选项
o = s:option(Value, "name", translate("Rule Name"))
o.width = "20%"
o.rmempty = false

-- 启用状态选项
o = s:option(Flag, "enabled", translate("Enabled"))
o.width = "10%"
o.default = "1"

-- 监听端口选项
o = s:option(Value, "listen_port", translate("Listen Port"))
o.width = "10%"
o.datatype = "port"
o.default = "80"

-- SSL状态显示
o = s:option(DummyValue, "ssl_status", translate("SSL"))
function o.cfgvalue(self, section)
    local ssl = m:get(section, "ssl") or "0"
    if ssl == "1" then
        return '<span class="status-success">已启用</span>'
    else
        return '<span class="status-pending">已禁用</span>'
    end
end

o.rawhtml = true

o.width = "10%"

-- 前端域名选项
o = s:option(Value, "frontend_domain", translate("Frontend Domain"))
o.width = "20%"
o.datatype = "hostname"
o.rmempty = false

-- 后端服务器显示
o = s:option(DummyValue, "backend_server", translate("Backend Server"))
function o.cfgvalue(self, section)
    local backend_ip = m:get(section, "backend_ip") or ""
    local backend_port = m:get(section, "backend_port") or ""
    if backend_ip and backend_port then
        return backend_ip .. ":" .. backend_port
    end
    return "-"
end
o.width = "20%"

-- 负载均衡模式显示
o = s:option(DummyValue, "balance_display", translate("Load Balance"))
function o.cfgvalue(self, section)
    local balance = m:get(section, "balance_mode") or "roundrobin"
    local modes = {
        roundrobin = "Round Robin",
        static_rr = "Static RR",
        leastconn = "Least Conn",
        source = "Source IP",
        uri = "URI Hash"
    }
    return modes[balance] or balance
end
o.width = "10%"

-- 操作按钮显示
o = s:option(DummyValue, "_actions", translate("Actions"))
function o.cfgvalue(self, section)
    return string.format(
        '<a href="%s" class="cbi-button cbi-button-edit">%s</a> ' ..
        '<a href="%s" class="cbi-button cbi-button-remove" onclick="return confirm(\'%s\')">%s</a>',
        luci.dispatcher.build_url("admin/services/domain/proxy/edit", section),
        translate("Edit"),
        luci.dispatcher.build_url("admin/services/domain/delete_proxy", section),
        translate("Confirm delete this proxy rule?"),
        translate("Delete")
    )
end
o.rawhtml = true
o.width = "10%"

-- 测试所有后端按钮
o = s:option(Button, "_test_all", translate("Test All Backends"))
o.inputtitle = translate("Test Connections")
o.inputstyle = "apply"
function o.write(self, section, value)
    luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/proxy/test_all"))
end

-- 重启HAProxy按钮
o = s:option(Button, "_restart", translate("Restart HAProxy"))
o.inputtitle = translate("Restart Now")
o.inputstyle = "apply"
function o.write(self, section, value)
    -- 执行重启命令
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
end

return m
