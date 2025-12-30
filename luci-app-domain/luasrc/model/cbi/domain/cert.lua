local m, s, o
local uci = require "luci.model.uci".cursor()

m = Map("domain", translate("Certificate Management"),
    translate("Manage SSL certificates using ACME (Let's Encrypt)."))

-- 添加CSS加载模板
m:append(Template("domain/css_loader"))

-- 证书配置列表部分
s = m:section(TypedSection, "certificate", translate("Certificate Settings"))
s.anonymous = false
s.addremove = true
s.template = "cbi/tblsection"
s.extedit = luci.dispatcher.build_url("admin/services/domain/cert/edit/%s")

function s.create(self, section)
    local sid = TypedSection.create(self, section)
    luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/cert/edit", sid))
end

-- 创建证书名称字段
o = s:option(Value, "name", translate("Certificate Name"))
o.width = "20%"
o.rmempty = false

-- 创建自动续期开关
o = s:option(Flag, "enabled", translate("Auto Renewal"))
o.width = "10%"
o.default = "1"

-- 创建主域名字段
o = s:option(Value, "primary_domain", translate("Primary Domain"))
o.width = "15%"
o.datatype = "hostname"
o.rmempty = false

-- 创建附加域名显示
o = s:option(DummyValue, "additional_domains", translate("Additional Domains"))
function o.cfgvalue(self, section)
    local domains = m:get(section, "additional_domains")
    if type(domains) == "table" then
        return table.concat(domains, ", ")
    elseif domains then
        return domains
    end
    return "-"
end
o.width = "20%"

-- 创建证书类型显示
o = s:option(DummyValue, "cert_type", translate("Type"))
function o.cfgvalue(self, section)
    local type = m:get(section, "certificate_type") or "acme"
    local types = {
        acme = "ACME",
        manual = "Manual",
        existing = "Existing"
    }
    return types[type] or type
end
o.width = "10%"

-- 创建证书状态显示
o = s:option(DummyValue, "status", translate("Status"))
function o.cfgvalue(self, section)
    local primary = m:get(section, "primary_domain")
    if primary then
        local cert_path = "/etc/ssl/certs/" .. primary .. ".crt"
        local f = io.open(cert_path, "r")
        if f then
            f:close()
            -- 检查证书是否在30天内过期
            local expiry = os.execute(string.format("openssl x509 -in %s -checkend 2592000 -noout 2>/dev/null", cert_path))
            if expiry == 0 then
                return '<span class="status-success">有效 (30+ 天)</span>'
            else
                return '<span class="status-warning">即将过期</span>'
            end
        else
            return '<span class="status-pending">未签发</span>'
        end
    end
    return '<span class="status-pending">未知</span>'
end
o.rawhtml = true
o.width = "15%"

-- 创建操作按钮显示
o = s:option(DummyValue, "_actions", translate("Actions"))
function o.cfgvalue(self, section)
    return string.format(
        '<a href="%s" class="cbi-button cbi-button-edit">%s</a> ' ..
        '<a href="%s" class="cbi-button cbi-button-action" onclick="return confirm(\'%s\')">%s</a>',
        luci.dispatcher.build_url("admin/services/domain/cert/edit", section),
        translate("Edit"),
        luci.dispatcher.build_url("admin/services/domain/cert/renew", section),
        translate("Confirm renew this certificate?"),
        translate("Renew")
    )
end
o.rawhtml = true
o.width = "10%"

-- 创建检查所有证书按钮
o = s:option(Button, "_check_all", translate("Check All Certificates"))
o.inputtitle = translate("Check Now")
o.inputstyle = "apply"
function o.write(self, section, value)
    luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/cert/status"))
end

o = s:option(Button, "_renew_all", translate("Renew All Expiring"))
o.inputtitle = translate("Renew Now")
o.inputstyle = "apply"
function o.write(self, section, value)
    luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/cert/renew_all"))
end

return m
