-- domain/proxy.lua - 反向代理管理控制器
module("luci.controller.domain.proxy", package.seeall)

local uci = require "luci.model.uci".cursor()
local json = require "luci.jsonc"
-- 错误处理模块
local errors = require "luci.controller.domain.errors"
-- 日志模块
local logger = require "luci.controller.domain.logger"

function index()
    -- 反向代理页面
    entry({"admin", "services", "domain", "proxy"}, cbi("domain/proxy"), _("Reverse Proxy"), 20)
    entry({"admin", "services", "domain", "proxy", "edit"}, form("domain/proxy_detail"), _("Edit Proxy Rule"), 21).leaf = true
    entry({"admin", "services", "domain", "proxy", "edit", ":id"}, form("domain/proxy_detail"), _("Edit Proxy Rule"), 22).leaf = true
    
    -- AJAX API
    entry({"admin", "services", "domain", "test_backend"}, call("test_backend_connection")).leaf = true
end

-- 测试后端连接函数
    local data
    local success, err = pcall(function()
        data = json.parse(luci.http.content())
    end)
    
    if not success then
        logger.error("global", "Invalid JSON format in test_backend_connection: " .. err)
        return errors.bad_request("Invalid JSON format: " .. err)
    end
    
    -- 验证请求参数
    if not data.ip or not data.port then
        logger.error("global", "Missing IP or port in test_backend_connection")
        return errors.bad_request("Missing IP or port")
    end
    
    -- 验证IP地址格式
        return ip:match("^%d+%.%d+%.%d+%.%d+$") or ip:match("^[%x:]+$")
    end
    
    if not is_valid_ip(data.ip) then
        logger.error("global", "Invalid IP format in test_backend_connection: " .. data.ip)
        return errors.bad_request("Invalid IP format")
    end
    
    -- 将端口转换为数字并验证范围
    if not port or port < 1 or port > 65535 then
        logger.error("global", "Invalid port number in test_backend_connection: " .. data.port)
        return errors.bad_request("Invalid port number")
    end
    
    local result = {success = false}
    local sys = require "luci.sys"
    
    logger.info("global", string.format("Testing backend connection to %s:%d", data.ip, port))
    
    -- 构建测试命令
    local output = sys.exec(cmd)
    
    if output:match("succeeded") then
        result.success = true
        result.ping = 0 -- 记录连接成功日志
    else
        result.error = output
        logger.warn("global", string.format("Backend connection test failed for %s:%d: %s", data.ip, port, output))
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end
