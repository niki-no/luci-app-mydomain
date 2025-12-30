-- domain/system.lua - 系统管理控制器
module("luci.controller.domain.system", package.seeall)

local uci = require "luci.model.uci".cursor()
local json = require "luci.jsonc"
-- 错误处理模块
local errors = require "luci.controller.domain.errors"
-- 日志模块
local logger = require "luci.controller.domain.logger"

function index()
    -- 系统API接口
    entry({"admin", "services", "domain", "get_domain_stats"}, call("get_domain_stats")).leaf = true
    entry({"admin", "services", "domain", "get_recent_logs"}, call("get_recent_logs")).leaf = true
    entry({"admin", "services", "domain", "test_ip_source"}, call("test_ip_source")).leaf = true
    entry({"admin", "services", "domain", "apply_config"}, call("apply_configuration")).leaf = true
end

-- 获取域名统计信息函数
    local stats = {
        total = 0,
        enabled = 0,
        successful = 0,
        failed = 0
    }
    local fs = require "nixio.fs"
    
    uci:foreach("domain", "domain", function(s)
        stats.total = stats.total + 1
        if s.enabled == "1" then
            stats.enabled = stats.enabled + 1
        end
        
        local status_file = "/tmp/ddns_" .. s[".name"] .. ".status"
        if fs.access(status_file) then
            local content = fs.readfile(status_file)
            if content then
                if content:match("status:success") then
                    stats.successful = stats.successful + 1
                elseif content:match("status:failed") then
                    stats.failed = stats.failed + 1
                end
            end
        end
    end)
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(stats)
end

-- 获取最近日志函数
    local logs = {}
    local log_file = "/var/log/domain.log"
    local fs = require "nixio.fs"
    
    if fs.access(log_file) then
        local lines = {}
        for line in io.lines(log_file) do
            table.insert(lines, line)
        end
        
        local start = math.max(1, #lines - 100 + 1)
        for i = start, #lines do
            table.insert(logs, lines[i])
        end
    end
    
    luci.http.prepare_content("text/plain")
    luci.http.write(table.concat(logs, "\n"))
end

-- 测试IP获取源函数
    local data
    local success, err = pcall(function()
        data = json.parse(luci.http.content())
    end)
    
    if not success then
        return errors.bad_request("Invalid JSON format: " .. err)
    end
    
    local result = {success = false, ip = "", error = "", source = data.source}
    
    local valid_interfaces = {"wan", "lan", "eth0", "eth1", "wan6", "br-lan"}
    
    -- IP获取源：接口 -> Web服务 -> URL
    local ip_sources = {
        ipv4 = {
            ["myip.ipip.net"] = "https://myip.ipip.net",
            ["ddns.oray.com"] = "https://ddns.oray.com/checkip",
            ["ip.3322.net"] = "https://ip.3322.net",
            ["4.ipw.cn"] = "https://4.ipw.cn",
            ["v4.yinghualuo.cn"] = "https://v4.yinghualuo.cn/bejson"
        },
        ipv6 = {
            ["speed.neu6.edu.cn"] = "https://speed.neu6.edu.cn/getIP.php",
            ["v6.ident.me"] = "https://v6.ident.me",
            ["6.ipw.cn"] = "https://6.ipw.cn",
            ["v6.yinghualuo.cn"] = "https://v6.yinghualuo.cn/bejson"
        }
    }
    
    -- 验证请求参数
    if not data.type or not data.source or not data.value then
        return errors.bad_request("Invalid parameters: type, source and value are required")
    end
    
    local cmd = ""
    if data.source:match("interface") then
        -- 检查是否为有效的接口
        local valid_interface = false
        for _, iface in ipairs(valid_interfaces) do
            if iface == data.value then
                valid_interface = true
                break
            end
        end
        
        if valid_interface then
            if data.type == "ipv4" then
                cmd = string.format("ifconfig %s 2>/dev/null | grep -o 'inet addr:[^ ]*' | cut -d: -f2", data.value)
            elseif data.type == "ipv6" then
                cmd = string.format("ifconfig %s 2>/dev/null | grep -o 'inet6 addr:[^ ]*' | cut -d: -f3 | head -1", data.value)
            end
        else
            return errors.bad_request("Invalid interface name: " .. data.value)
        end
    elseif data.source:match("web") then
        -- 验证Web源是否有效
            return errors.bad_request(string.format("Invalid web source for %s: %s", data.type, data.value))
        end
        
        local url = ip_sources[data.type][data.value]
        if url then
            -- IP获取源处理
            if data.value == "myip.ipip.net" then
                -- 解析返回的IP地址格式：当前 IP：x.x.x.x  来自于：xx                cmd = string.format("curl -s -f '%s' | grep -o '?IP?]*' | cut -d?-f2", url)
            elseif data.value == "ddns.oray.com" then
                -- 解析返回的IP地址格式：Current IP Address: x.x.x.x
                cmd = string.format("curl -s -f '%s' | grep -o 'Current IP Address: [^ ]*' | cut -d: -f2 | tr -d ' '", url)
            elseif data.value:match("%.bejson$") then
                -- 解析JSON格式的IP地址返回                cmd = string.format("curl -s -f '%s' | grep -o '\"ip\":\"[^\"]*' | cut -d\" -f4", url)
            else
                -- 
                cmd = string.format("curl -s -f '%s' | tr -d '\n\r'", url)
            end
        end
    else
        return errors.bad_request("Invalid source type: " .. data.source)
    end
    
    if cmd ~= "" then
        local sys = require "luci.sys"
        result.ip = sys.exec(cmd):gsub("%s+", "")
        result.success = result.ip ~= ""
    end
    
    if not result.success then
        result.error = "Failed to get IP address"
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 应用配置函数
function apply_configuration()
    local result = {success = true, message = "Configuration applied successfully"}
    
    logger.info("global", "Applying configuration changes")
    
    -- 生成HAProxy配置    local nixio = require "nixio"
    logger.info("global", "Generating HAProxy configuration")
    
    local pid, err = nixio.fork()
    if pid == 0 then
        nixio.chdir("/")
        nixio.dup(nixio.open("/dev/null", "w")), nixio.stderr)
        nixio.dup(nixio.open("/dev/null", "w")), nixio.stdout)
        nixio.exec("/usr/lib/domain/generate_haproxy_config.sh", "generate")
        os.exit(1)
    elseif not pid then
        result.success = false
        result.error = "Failed to generate HAProxy configuration"
        logger.error("global", "Failed to generate HAProxy configuration: " .. err)
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
        return
    end
    
    -- 等待配置生成完成
    
    -- 需要重启的服务列表
    
    for _, service in ipairs(services) do
        logger.info("global", "Restarting service: " .. service)
        local pid, err = nixio.fork()
        if pid == 0 then
            nixio.chdir("/")
            nixio.dup(nixio.open("/dev/null", "w")), nixio.stderr)
            nixio.dup(nixio.open("/dev/null", "w")), nixio.stdout)
            nixio.exec("/etc/init.d/" .. service, "restart")
            os.exit(1)
        elseif not pid then
            result.success = false
            result.error = "Failed to restart service: " .. service
            logger.error("global", "Failed to restart service: " .. service .. ": " .. err)
            break
        else
            logger.info("global", "Successfully triggered restart for service: " .. service)
        end
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end
