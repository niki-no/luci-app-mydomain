-- domain/certificate.lua - 证书管理控制器
module("luci.controller.domain.certificate", package.seeall)

local uci = require "luci.model.uci".cursor()
local json = require "luci.jsonc"
local fs = require "nixio.fs"
-- 错误处理模块
local errors = require "luci.controller.domain.errors"
-- 日志模块
local logger = require "luci.controller.domain.logger"

function index()
    -- 证书状态页面    entry({"admin", "services", "domain", "cert", "status"}, template("domain/cert_status"), _("Certificate Status"), 33).leaf = true
    entry({"admin", "services", "domain", "cert", "edit"}, form("domain/cert_detail"), _("Edit Certificate"), 31).leaf = true
    entry({"admin", "services", "domain", "cert", "edit", ":id"}, form("domain/cert_detail"), _("Edit Certificate"), 32).leaf = true
    
    -- AJAX API
    entry({"admin", "services", "domain", "get_certs"}, call("get_certificates")).leaf = true
    entry({"admin", "services", "domain", "get_cert_detail", ":id"}, call("get_certificate_detail")).leaf = true
    entry({"admin", "services", "domain", "bulk_check_certs"}, call("bulk_check_certificates")).leaf = true
    entry({"admin", "services", "domain", "bulk_renew_certs"}, call("bulk_renew_certificates")).leaf = true
    entry({"admin", "services", "domain", "validate_cert"}, call("validate_certificate")).leaf = true
    entry({"admin", "services", "domain", "cert", "check", ":id"}, call("check_certificate")).leaf = true
    entry({"admin", "services", "domain", "cert", "request", ":id"}, call("request_certificate")).leaf = true
    entry({"admin", "services", "domain", "cert", "renew", ":id"}, call("renew_certificate")).leaf = true
end

-- 获取证书列表函数
function get_certificates()
    local result = {}
    local uci = require "luci.model.uci".cursor()
    
    uci:foreach("acme", "acme", function(s)
        if s.main_domain then
            table.insert(result, {
                id = s[".name"],
                domain = s.main_domain,
                domains = s.domains or "",
                status = s.state or "unknown",
                path = s.cert_dir or ""
            })
        end
    end)
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 获取证书详情函数
function get_certificate_detail()
    local id = luci.dispatcher.context.path[5]
    local sys = require "luci.sys"
    
    if not id then
        return errors.bad_request("Certificate ID is required")
    end
    
    if not id:match("^[a-zA-Z0-9_-]+$") then
        return errors.bad_request("Invalid certificate ID format")
    end
    
    local cert_path = "/etc/ssl/certs/" .. id .. ".crt"
    local result = {success = true}
    
    if fs.access(cert_path) then
        local cmd = string.format("openssl x509 -in %s -noout -text 2>/dev/null", cert_path)
        local info = sys.exec(cmd)
        
        if info then
            result.cert = {
                subject = info:match("Subject: *(.+)") or "",
                issuer = info:match("Issuer: *(.+)") or "",
                not_before = info:match("Not Before: *(.+)") or "",
                not_after = info:match("Not After : *(.+)") or "",
                algorithm = info:match("Public Key Algorithm: *(.+)") or "",
                key_length = info:match("RSA Public-Key: *(%d+)") or info:match("Public-Key: *(%d+)") or "",
                signature_alg = info:match("Signature Algorithm: *(.+)") or "",
                serial = info:match("Serial Number: *(.+)") or "",
                certificate_content = fs.readfile(cert_path) or ""
            }
        end
    else
        return errors.not_found("Certificate file not found")
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 批量检查证书状态函数
function bulk_check_certificates()
    local stats = {valid = 0, expiring = 0, expired = 0}
    local sys = require "luci.sys"
    
    uci:foreach("domain", "certificate", function(s)
        local cert_path = s.cert_path or "/etc/ssl/certs/" .. (s.primary_domain or s[".name"]) .. ".crt"
        if fs.access(cert_path) then
            local expiry = sys.exec(string.format("openssl x509 -in %s -enddate -noout 2>/dev/null | cut -d= -f2", cert_path))
            if expiry then
                local days_left = calculate_days_left(expiry)
                
                if days_left > 30 then
                    stats.valid = stats.valid + 1
                elseif days_left > 0 then
                    stats.expiring = stats.expiring + 1
                else
                    stats.expired = stats.expired + 1
                end
            end
        end
    end)
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(stats)
end

-- 批量续期证书函数
function bulk_renew_certificates()
    local data
    local success, err = pcall(function()
        data = json.parse(luci.http.content())
    end)
    
    if not success then
        return errors.bad_request("Invalid JSON format: " .. err)
    end
    
    if not data.ids or type(data.ids) ~= "table" then
        return errors.bad_request("Invalid request format: ids must be an array")
    end
    
    local result = {success = 0, failed = 0}
    local nixio = require "nixio"
    
    for _, cert_id in ipairs(data.ids) do
        -- 遍历每个证书ID进行续期
        if cert_id and cert_id:match("^[a-zA-Z0-9_-]+$") then
            local args = {"/usr/lib/acme/acme.sh", "--renew", "-d", cert_id}
            local pid = nixio.fork()
            
            if pid == 0 then
                nixio.chdir("/")
                nixio.dup(nixio.open("/dev/null", "w")), nixio.stderr)
                nixio.dup(nixio.open("/dev/null", "w")), nixio.stdout)
                nixio.exec(unpack(args))
                os.exit(1)
            elseif pid > 0 then
                local _, status = nixio.wait(pid)
                if nixio.orexitstatus(status) == 0 then
                    result.success = result.success + 1
                else
                    result.failed = result.failed + 1
                end
            else
                result.failed = result.failed + 1
            end
        else
            result.failed = result.failed + 1
        end
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 验证证书函数
function validate_certificate()
    local data
    local success, err = pcall(function()
        data = json.parse(luci.http.content())
    end)
    
    if not success then
        return errors.bad_request("Invalid JSON format: " .. err)
    end
    
    if not data.certificate then
        return errors.bad_request("Missing certificate data")
    end
    
    local temp_file = "/tmp/validate_cert.pem"
    local f = io.open(temp_file, "w")
    local result = {valid = false}
    local sys = require "luci.sys"
    
    if f then
        f:write(data.certificate)
        f:close()
        
        local info = sys.exec(string.format("openssl x509 -in %s -noout -subject -issuer -dates 2>/dev/null", temp_file))
        fs.unlink(temp_file)
        
        if info then
            result.valid = true
            result.info = info
        else
            result.error = "Invalid certificate format"
        end
    else
        return errors.internal_server_error("Failed to create temporary file")
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 检查证书状态函数
function check_certificate()
    local id = luci.dispatcher.context.path[5]
    local sys = require "luci.sys"
    
    if not id then
        return errors.bad_request("Certificate ID is required")
    end
    
    if not id:match("^[a-zA-Z0-9_-]+$") then
        return errors.bad_request("Invalid certificate ID format")
    end
    
    local config = uci:get_all("domain", id)
    if not config then
        return errors.not_found("Certificate configuration not found")
    end
    
    local cert_path = config.cert_path or "/etc/ssl/certs/" .. (config.primary_domain or "default") .. ".crt"
    local result = {valid = false}
    
    if fs.access(cert_path) then
        local info = sys.exec(string.format("openssl x509 -in %s -noout -subject -issuer -dates 2>/dev/null", cert_path))
        if info then
            result.valid = true
            result.subject = info:match("subject= *(.+)") or ""
            result.issuer = info:match("issuer= *(.+)") or ""
            result.not_before = info:match("notBefore= *(.+)") or ""
            result.not_after = info:match("notAfter= *(.+)") or ""
            
            local expiry_str = result.not_after
            if expiry_str then
                local days_left = calculate_days_left(expiry_str)
                result.days_left = days_left
            end
        end
    else
        return errors.not_found("Certificate file not found")
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 请求证书函数
function request_certificate()
    local id = luci.dispatcher.context.path[5]
    
    if not id then
        logger.error("global", "Certificate ID is required in request_certificate")
        return errors.bad_request("Certificate ID is required")
    end
    
    if not id:match("^[a-zA-Z0-9_-]+$") then
        logger.error("global", "Invalid certificate ID format in request_certificate: " .. tostring(id))
        return errors.bad_request("Invalid certificate ID format")
    end
    
    local config = uci:get_all("domain", id)
    if not config then
        logger.error("global", "Certificate configuration not found in request_certificate: " .. id)
        return errors.not_found("Certificate configuration not found")
    end
    
    if not config.primary_domain then
        logger.error(id, "Primary domain is required for certificate request")
        return errors.bad_request("Primary domain is required")
    end
    
    logger.info(id, "Starting certificate request for domain: " .. config.primary_domain)
    
    local args = {"/usr/lib/acme/acme.sh", "--issue", "--dns", config.dns_provider or "dns_cf", "-d", config.primary_domain}
    local nixio = require "nixio"
    local sys = require "luci.sys"
    local result = {success = false, message = "Failed to request certificate"}
    
    local pid, err = nixio.fork()
    
    if pid == 0 then
        nixio.chdir("/")
        local log_file = nixio.open("/tmp/acme.log", "w")
        if log_file then
            nixio.dup(log_file), nixio.stderr)
            nixio.dup(log_file), nixio.stdout)
            log_file:close()
        end
        nixio.exec(unpack(args))
        os.exit(1)
    elseif pid > 0 then
        local _, status = nixio.wait(pid)
        if nixio.orexitstatus(status) == 0 then
            result.success = true
            result.message = "Certificate requested successfully"
            logger.info(id, "Certificate requested successfully for domain: " .. config.primary_domain)
        else
            result.message = "Request failed"
            result.error = sys.exec("tail -20 /tmp/acme.log 2>/dev/null")
            logger.error(id, "Failed to request certificate for domain: " .. config.primary_domain)
        end
    else
        logger.error(id, "Failed to execute command for certificate request: " .. err)
        return errors.internal_server_error("Failed to execute command: " .. err)
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 续期证书函数
function renew_certificate()
    local id = luci.dispatcher.context.path[5]
    
    if not id then
        logger.error("global", "Certificate ID is required in renew_certificate")
        return errors.bad_request("Certificate ID is required")
    end
    
    if not id:match("^[a-zA-Z0-9_-]+$") then
        logger.error("global", "Invalid certificate ID format in renew_certificate: " .. tostring(id))
        return errors.bad_request("Invalid certificate ID format")
    end
    
    local config = uci:get_all("domain", id)
    if not config then
        logger.error("global", "Certificate configuration not found in renew_certificate: " .. id)
        return errors.not_found("Certificate configuration not found")
    end
    
    if not config.primary_domain then
        logger.error(id, "Primary domain is required for certificate renewal")
        return errors.bad_request("Primary domain is required")
    end
    
    logger.info(id, "Starting certificate renewal for domain: " .. config.primary_domain)
    
    local args = {"/usr/lib/acme/acme.sh", "--renew", "-d", config.primary_domain, "--dns", config.dns_provider or "dns_cf"}
    local nixio = require "nixio"
    local sys = require "luci.sys"
    local result = {success = false, message = "Failed to renew certificate"}
    
    local pid, err = nixio.fork()
    
    if pid == 0 then
        nixio.chdir("/")
        local log_file = nixio.open("/tmp/acme_renew.log", "w")
        if log_file then
            nixio.dup(log_file), nixio.stderr)
            nixio.dup(log_file), nixio.stdout)
            log_file:close()
        end
        nixio.exec(unpack(args))
        os.exit(1)
    elseif pid > 0 then
        local _, status = nixio.wait(pid)
        if nixio.orexitstatus(status) == 0 then
            result.success = true
            result.message = "Certificate renewed successfully"
            logger.info(id, "Certificate renewed successfully for domain: " .. config.primary_domain)
        else
            result.message = "Renewal failed"
            result.error = sys.exec("tail -20 /tmp/acme_renew.log 2>/dev/null")
            logger.error(id, "Failed to renew certificate for domain: " .. config.primary_domain)
        end
    else
        logger.error(id, "Failed to execute command for certificate renewal: " .. err)
        return errors.internal_server_error("Failed to execute command: " .. err)
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 计算证书剩余天数函数
function calculate_days_left(expiry_str)
    if not expiry_str then return 0 end
    
    -- OpenSSL日期格式映射
    local month_map = {
        Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
        Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12
    }
    
    local day, month_str, year, time = expiry_str:match("(%d+)%s+(%w+)%s+(%d+)%s+(%d+:%d+:%d+) GMT")
    if day and month_str and year and time then
        local month = month_map[month_str]
        if month then
            local expiry_date = os.time({year=year, month=month, day=day, hour=0, min=0, sec=0})
            local now = os.time()
            local diff = expiry_date - now
            return math.floor(diff / (60 * 60 * 24))
        end
    end
    
    return 0
end
