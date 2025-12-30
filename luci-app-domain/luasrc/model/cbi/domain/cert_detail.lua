local m, s, o
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local fs = require "nixio.fs"

-- 
local config_id = arg[1]

m = Map("domain", translate("Certificate Management"),
    translate("Manage SSL certificates with ACME and manual options."))

m.redirect = luci.dispatcher.build_url("admin/services/domain/cert")

-- 添加CSS加载模板
m:append(Template("domain/css_loader"))

if config_id then
    m.title = translate("Edit Certificate Configuration")
else
    m.title = translate("Add Certificate Configuration")
    config_id = luci.util.genid()
end

-- 创建证书配置部分
s = m:section(NamedSection, config_id, "certificate", translate("Basic Settings"))
s.anonymous = false
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable Auto Renewal"))
o.default = "1"

o = s:option(Value, "name", translate("Configuration Name"))
o.rmempty = false

-- 创建域名设置选项卡
s:tab("domains", translate("Domain Settings"))

o = s:taboption("domains", Value, "primary_domain", translate("Primary Domain"))
o.datatype = "hostname"
o.rmempty = false
o.placeholder = "example.com"

o = s:taboption("domains", DynamicList, "additional_domains", translate("Additional Domains"))
o.datatype = "hostname"
o.placeholder = "www.example.com"
o:value("*.example.com", "Wildcard Domain")
o:value("mail.example.com", "Mail Server")
o:value("api.example.com", "API Server")

-- 创建域名摘要显示
o = s:taboption("domains", DummyValue, "_domains_summary", translate("Domain Summary"))
function o.cfgvalue(self, section)
    local primary = m:get(section, "primary_domain") or ""
    local additional = m:get(section, "additional_domains") or {}
    local domains = {}
    
    if primary ~= "" then
        table.insert(domains, primary)
    end
    
    if type(additional) == "table" then
        for _, domain in ipairs(additional) do
            table.insert(domains, domain)
        end
    end
    
    if #domains > 0 then
        return table.concat(domains, "<br>")
    else
        return translate("No domains configured")
    end
end
o.rawhtml = true

-- 创建证书类型选项卡
s:tab("cert_type", translate("Certificate Type"))

o = s:taboption("cert_type", ListValue, "certificate_type", translate("Certificate Source"))
o:value("acme", translate("ACME (Let's Encrypt)"))
o:value("manual", translate("Manual Upload"))
o:value("existing", translate("Existing Certificate"))
o.default = "acme"

-- 创建ACME设置选项卡
s:tab("acme_settings", translate("ACME Settings"))
s:depends("certificate_type", "acme")

o = s:taboption("acme_settings", ListValue, "acme_server", translate("ACME Server"))
o:value("letsencrypt", "Let's Encrypt Production")
o:value("letsencrypt_test", "Let's Encrypt Staging")
o:value("zerossl", "ZeroSSL")
o:value("buypass", "Buypass")
o:value("custom", translate("Custom ACME Server"))
o.default = "letsencrypt"

o = s:taboption("acme_settings", Value, "acme_email", translate("Email Address"))
o.datatype = "email"
o.rmempty = false
o.placeholder = "admin@example.com"

o = s:taboption("acme_settings", ListValue, "key_type", translate("Key Type"))
o:value("ec-256", "ECDSA P-256 (Recommended)")
o:value("ec-384", "ECDSA P-384")
o:value("rsa-2048", "RSA 2048")
o:value("rsa-3072", "RSA 3072")
o:value("rsa-4096", "RSA 4096")
o.default = "ec-256"

-- 创建验证方法选项卡
s:tab("validation", translate("Validation Method"))

o = s:taboption("validation", ListValue, "challenge_type", translate("Challenge Type"))
o:value("http-01", "HTTP-01 Challenge (Web Server)")
o:value("dns-01", "DNS-01 Challenge (DNS API)")
o:value("tls-alpn-01", "TLS-ALPN-01 Challenge")
o.default = "http-01"

-- 创建HTTP验证端口设置
o = s:taboption("validation", Value, "http_port", translate("HTTP Challenge Port"))
o:depends("challenge_type", "http-01")
o.default = "80"
o.datatype = "port"

o = s:taboption("validation", Value, "tls_port", translate("TLS Challenge Port"))
o:depends("challenge_type", "tls-alpn-01")
o.default = "443"
o.datatype = "port"

-- 创建DNS提供商选项卡
s:tab("dns_provider", translate("DNS Provider"))
s:depends("challenge_type", "dns-01")

o = s:taboption("dns_provider", ListValue, "dns_provider", translate("DNS Provider"))
o:value("", translate("-- Select Provider --"))
o:value("cloudflare", "Cloudflare")
o:value("aliyun", "Aliyun (阿里云)")
o:value("dnspod", "DNSPod (腾讯云)")
o:value("huaweicloud", "Huawei Cloud")
o:value("godaddy", "GoDaddy")
o:value("route53", "AWS Route53")
o:value("digitalocean", "DigitalOcean")
o:value("vultr", "Vultr")
o:value("custom", translate("Custom Script"))

o = s:taboption("dns_provider", Value, "dns_api_key", translate("API Key"))
o.password = true
o:depends("dns_provider", "cloudflare")
o:depends("dns_provider", "digitalocean")
o:depends("dns_provider", "vultr")

o = s:taboption("dns_provider", Value, "dns_secret_key", translate("Secret Key"))
o.password = true
o:depends("dns_provider", "aliyun")
o:depends("dns_provider", "dnspod")
o:depends("dns_provider", "route53")

o = s:taboption("dns_provider", Value, "dns_script", translate("Custom Script Path"))
o:depends("dns_provider", "custom")
o.datatype = "file"

-- 创建手动证书选项卡
s:tab("manual_cert", translate("Manual Certificate"))
s:depends("certificate_type", "manual")

o = s:taboption("manual_cert", TextValue, "certificate_content", translate("Certificate Content"))
o.rows = 10
o.wrap = "off"
o.rmempty = false
o.datatype = "string"
-- 证书内容验证函数
function o.validate(self, value, section)
    if value then
        -- 验证证书格式
            if not value:match("^-----BEGIN CERTIFICATE-----.*-----END CERTIFICATE-----$"s) then
            return nil, translate("Invalid PEM certificate format")
        end
        -- 验证证书大小
            if #value > 102400 then -- 100KB limit
            return nil, translate("Certificate content too large")
        end
    end
    return value
end

o = s:taboption("manual_cert", TextValue, "private_key", translate("Private Key"))
o.rows = 10
o.wrap = "off"
o.rmempty = false
o.password = true
-- 私钥验证函数
function o.validate(self, value, section)
    if value then
        -- 验证私钥格式
            if not value:match("^-----BEGIN (RSA )?PRIVATE KEY-----.*-----END (RSA )?PRIVATE KEY-----$"s) then
            return nil, translate("Invalid PEM private key format")
        end
        -- 验证私钥大小
            if #value > 102400 then -- 100KB limit
            return nil, translate("Private key content too large")
        end
    end
    return value
end

o = s:taboption("manual_cert", TextValue, "ca_certificate", translate("CA Certificate (Optional)"))
o.rows = 5
o.wrap = "off"

-- 创建现有证书选项卡
s:tab("existing_cert", translate("Existing Certificate"))
s:depends("certificate_type", "existing")

o = s:taboption("existing_cert", Value, "cert_path", translate("Certificate Path"))
o.datatype = "file"
o.placeholder = "/etc/ssl/certs/example.com.crt"

o = s:taboption("existing_cert", Value, "key_path", translate("Private Key Path"))
o.datatype = "file"
o.placeholder = "/etc/ssl/private/example.com.key"

o = s:taboption("existing_cert", Value, "ca_path", translate("CA Bundle Path (Optional)"))
o.datatype = "file"
o.placeholder = "/etc/ssl/certs/ca-bundle.crt"

-- 创建续期设置选项卡
s:tab("renewal", translate("Renewal Settings"))

o = s:taboption("renewal", Value, "renew_days", translate("Renew Before Expiry (days)"))
o.default = "30"
o.datatype = "range(1,60)"
o:value("7", "7 days")
o:value("15", "15 days")
o:value("30", "30 days")
o:value("45", "45 days")

o = s:taboption("renewal", Value, "renew_hour", translate("Renewal Hour (0-23)"))
o.default = "3"
o.datatype = "range(0,23)"

o = s:taboption("renewal", Flag, "post_renew_hook", translate("Run Post-Renewal Hook"))
o.default = "0"

o = s:taboption("renewal", Value, "post_renew_script", translate("Post-Renewal Script"))
o:depends("post_renew_hook", "1")
o.datatype = "file"

-- 创建高级设置选项卡
s:tab("advanced", translate("Advanced Settings"))

o = s:taboption("advanced", Value, "key_length", translate("Key Length"))
o.default = "2048"
o.datatype = "uinteger"
o:value("2048", "2048 bits")
o:value("3072", "3072 bits")
o:value("4096", "4096 bits")

o = s:taboption("advanced", ListValue, "hash_algorithm", translate("Hash Algorithm"))
o:value("sha256", "SHA-256")
o:value("sha384", "SHA-384")
o:value("sha512", "SHA-512")
o.default = "sha256"

o = s:taboption("advanced", Value, "cert_dir", translate("Certificate Directory"))
o.default = "/etc/ssl/certs"
o.datatype = "directory"

o = s:taboption("advanced", Value, "key_dir", translate("Private Key Directory"))
o.default = "/etc/ssl/private"
o.datatype = "directory"

-- 创建证书状态选项卡
s:tab("status", translate("Certificate Status"))

o = s:taboption("status", DummyValue, "_cert_info", translate("Certificate Information"))
function o.cfgvalue(self, section)
    local cert_path = m:get(section, "cert_path") or "/etc/ssl/certs/" .. (m:get(section, "primary_domain") or "default") .. ".crt"
    
    if fs.access(cert_path) then
        local info = sys.exec(string.format("openssl x509 -in %s -noout -text 2>/dev/null | grep -E 'Subject:|Issuer:|Not Before:|Not After :'", cert_path))
        if info and #info > 0 then
            return '<pre style="background:#f5f5f5;padding:10px;border-radius:3px">' .. 
                   luci.util.pcdata(info) .. '</pre>'
        end
    end
    
    return '<span class="status-pending">' .. translate("No certificate found or not yet issued") .. '</span>'
end
o.rawhtml = true

o = s:taboption("status", DummyValue, "_cert_status", translate("Validity Status"))
function o.cfgvalue(self, section)
    local cert_path = m:get(section, "cert_path") or "/etc/ssl/certs/" .. (m:get(section, "primary_domain") or "default") .. ".crt"
    
    if fs.access(cert_path) then
        local expiry = sys.exec(string.format("openssl x509 -in %s -enddate -noout 2>/dev/null | cut -d= -f2", cert_path))
        if expiry then
            local days_left = calculate_days_left(expiry)
            
            if days_left > 30 then
                return string.format('<span class="status-success">Valid (%d days remaining)</span>', days_left)
            elseif days_left > 0 then
                return string.format('<span class="status-warning">Expiring soon (%d days remaining)</span>', days_left)
            else
                return '<span class="status-failed">Expired</span>'
            end
        end
    end
    
    return '<span class="status-pending">' .. translate("No certificate") .. '</span>'
end
o.rawhtml = true

o = s:taboption("status", Button, "_check_cert", translate("Check Certificate"))
o.inputtitle = translate("Check Now")
o.inputstyle = "apply"
function o.write(self, section, value)
    local primary_domain = m:get(section, "primary_domain")
    if primary_domain then
        luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/cert/check", section))
    end
end

o = s:taboption("status", Button, "_request_cert", translate("Request Certificate"))
o.inputtitle = translate("Request Now")
o.inputstyle = "apply"
function o.write(self, section, value)
    luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/cert/request", section))
end

o = s:taboption("status", Button, "_renew_cert", translate("Renew Certificate"))
o.inputtitle = translate("Renew Now")
o.inputstyle = "apply"
function o.write(self, section, value)
    luci.http.redirect(luci.dispatcher.build_url("admin/services/domain/cert/renew", section))
end

-- 计算证书剩余天数函数
function calculate_days_left(expiry_str)
    local month_map = {
        Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
        Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12
    }
    
    local month_str, day, time, year = expiry_str:match("(%a+)%s+(%d+)%s+(%d+:?%d+:?%d+)%s+(%d+)")
    local month = month_map[month_str] or 1
    
    if month and day and year then
        local expiry_time = os.time{year = tonumber(year), month = month, day = tonumber(day)}
        local now = os.time()
        local diff = expiry_time - now
        return math.floor(diff / 86400)
    end
    
    return 0
end

return m
