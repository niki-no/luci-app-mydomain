-- domain/domain.lua - DDNS管理控制器
module("luci.controller.domain.domain", package.seeall)

-- 导入模块
local uci = require "luci.model.uci".cursor()
local json = require "luci.jsonc"
local fs = require "nixio.fs"
-- 错误处理模块
local errors = require "luci.controller.domain.errors"
-- 日志模块
local logger = require "luci.controller.domain.logger"

function index()
    -- DDNS管理页面
    entry({"admin", "services", "domain", "domain", "overview"}, template("domain/domain_overview"), _("Domain Overview"), 11).leaf = true
    entry({"admin", "services", "domain", "domain", "edit"}, form("domain/domain"), nil).leaf = true
    entry({"admin", "services", "domain", "domain", "edit", ":id"}, form("domain/domain"), nil).leaf = true
    
    -- AJAX API
    entry({"admin", "services", "domain", "get_ddns_status", ":id"}, call("get_ddns_status")).leaf = true
    entry({"admin", "services", "domain", "get_ddns_logs"}, call("get_ddns_logs")).leaf = true
    entry({"admin", "services", "domain", "clear_ddns_logs"}, call("clear_ddns_logs")).leaf = true
    entry({"admin", "services", "domain", "force_update", ":id"}, call("force_update_domain")).leaf = true
    entry({"admin", "services", "domain", "bulk_enable"}, call("bulk_enable_domains")).leaf = true
    entry({"admin", "services", "domain", "bulk_disable"}, call("bulk_disable_domains")).leaf = true
    entry({"admin", "services", "domain", "bulk_update"}, call("bulk_update_domains")).leaf = true
    entry({"admin", "services", "domain", "toggle_enable"}, call("toggle_domain_enable")).leaf = true
    entry({"admin", "services", "domain", "delete_domain", ":id"}, call("delete_domain_config")).leaf = true
end

-- 获取DDNS状态函数
    local id = luci.dispatcher.context.path[5] or luci.http.formvalue("id")
    if not id then
        return errors.bad_request("Domain ID is required")
    end
    
    if not id:match("^[a-zA-Z0-9_-]+$") then
        return errors.bad_request("Invalid domain ID format")
    end
    
    local status_file = "/tmp/ddns_" .. id .. ".status"
    local result = {
        success = true,
        status = "unknown",
        message = "No status available"
    }
    
    if fs.access(status_file) then
        local content = fs.readfile(status_file)
        if content then
            local status, ip, time = content:match("status:(%w+)%s+ip:(%S+)%s+time:(.+)")
            if status then
                result.status = status
                result.ip = ip
                result.time = time
                result.message = string.format("Last update: %s (IP: %s)", time, ip)
            end
        end
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 获取DDNS日志函数
    local data = {logs = {}, stats = {total = 0, info = 0, error = 0, today = 0}}
    local log_file = "/var/log/domain.log"
    
    if fs.access(log_file) then
        local now = os.date("%Y-%m-%d")
        for line in io.lines(log_file) do
            local time, level, config, message = line:match("^(%d+-%d+-%d+ %d+:%d+:%d+) %[(%w+)%] %[([^%]]*)%] (.+)$")
            if time then
                table.insert(data.logs, {
                    time = time,
                    level = level,
                    config = config,
                    message = message
                })
                data.stats.total = data.stats.total + 1
                
                if level == "INFO" then
                    data.stats.info = data.stats.info + 1
                elseif level == "ERROR" then
                    data.stats.error = data.stats.error + 1
                end
                
                if time:sub(1, 10) == now then
                    data.stats.today = data.stats.today + 1
                end
            end
        end
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(data)
end

-- 清除DDNS日志函数
function clear_ddns_logs()
    local log_file = "/var/log/domain.log"
    local result = {success = false}
    
    -- 打开日志文件进行清空
    if f then
        f:close()
        result.success = true
    end
    
    -- 清空相关的DDNS日志和状态文件
    for file in fs.glob("/var/log/ddns_*.log") do
        fs.unlink(file)
    end
    
    for file in fs.glob("/tmp/ddns_*.status") do
        fs.unlink(file)
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 强制更新域名函数
    local id = luci.dispatcher.context.path[5]
    
    if not id then
        return errors.bad_request("Domain ID is required")
    end
    
    if not id:match("^[a-zA-Z0-9_-]+$") then
        return errors.bad_request("Invalid domain ID format")
    end
    
    -- 构建更新命令参数
    local nixio = require "nixio"
    local pid, err = nixio.fork()
    
    local result = {success = true, message = "Update triggered"}
    
    if pid == 0 then
        nixio.chdir("/")
        nixio.dup(nixio.open("/dev/null", "w")), nixio.stderr)
        nixio.dup(nixio.open("/dev/null", "w")), nixio.stdout)
        nixio.exec(unpack(args))
        os.exit(1)
    elseif not pid then
        result.success = false
        result.error = "Failed to trigger update: " .. err
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 执行批量启用操作function bulk_enable_domains()
    local data
    local success, err = pcall(function()
        data = json.parse(luci.http.content())
    end)
    
    if not success then
        logger.error("global", "Invalid JSON format in bulk_enable_domains: " .. err)
        return errors.bad_request("Invalid JSON format: " .. err)
    end
    
    if not data.ids or type(data.ids) ~= "table" then
        logger.error("global", "Invalid request format in bulk_enable_domains: ids must be an array")
        return errors.bad_request("Invalid request format: ids must be an array")
    end
    
    -- 验证域名ID格式
        if not id or not id:match("^[a-zA-Z0-9_-]+$") then
            logger.error("global", "Invalid domain ID format in bulk_enable_domains: " .. tostring(id))
            return errors.bad_request("Invalid domain ID format: " .. tostring(id))
        end
    end
    
    -- 删除相关的日志和状态文件
    local result = {success = true, message = "Domains enabled successfully"}
    
    for _, id in ipairs(data.ids or {}) do
        uci:set("domain", id, "enabled", "1")
        logger.info(id, "Domain enabled via bulk operation")
    end
    
    local commit_success, commit_err = pcall(function()
        uci:commit("domain")
    end)
    
    if not commit_success then
        logger.error("global", "Failed to save configuration in bulk_enable_domains: " .. commit_err)
        return errors.internal_server_error("Failed to save configuration: " .. commit_err)
    end
    
    logger.info("global", "Bulk enabled domains: " .. table.concat(data.ids, ", "))
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 批量禁用域名函数
    local data
    local success, err = pcall(function()
        data = json.parse(luci.http.content())
    end)
    
    if not success then
        logger.error("global", "Invalid JSON format in bulk_disable_domains: " .. err)
        return errors.bad_request("Invalid JSON format: " .. err)
    end
    
    if not data.ids or type(data.ids) ~= "table" then
        logger.error("global", "Invalid request format in bulk_disable_domains: ids must be an array")
        return errors.bad_request("Invalid request format: ids must be an array")
    end
    
    -- ?    for _, id in ipairs(data.ids or {}) do
        if not id or not id:match("^[a-zA-Z0-9_-]+$") then
            logger.error("global", "Invalid domain ID format in bulk_disable_domains: " .. tostring(id))
            return errors.bad_request("Invalid domain ID format: " .. tostring(id))
        end
    end
    
    local result = {success = true}
    
    for _, id in ipairs(data.ids or {}) do
        uci:set("domain", id, "enabled", "0")
        logger.info(id, "Domain disabled via bulk operation")
    end
    
    local commit_success, commit_err = pcall(function()
        uci:commit("domain")
    end)
    
    if not commit_success then
        logger.error("global", "Failed to save configuration in bulk_disable_domains: " .. commit_err)
        return errors.internal_server_error("Failed to save configuration: " .. commit_err)
    end
    
    logger.info("global", "Bulk disabled domains: " .. table.concat(data.ids, ", "))
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 批量更新域名函数
    local data
    local success, err = pcall(function()
        data = json.parse(luci.http.content())
    end)
    
    if not success then
        logger.error("global", "Invalid JSON format in bulk_update_domains: " .. err)
        return errors.bad_request("Invalid JSON format: " .. err)
    end
    
    if not data.ids or type(data.ids) ~= "table" then
        logger.error("global", "Invalid request format in bulk_update_domains: ids must be an array")
        return errors.bad_request("Invalid request format: ids must be an array")
    end
    
    local results = {success = 0, failed = 0}
    local nixio = require "nixio"
    
    logger.info("global", "Starting bulk update for domains: " .. table.concat(data.ids, ", "))
    
    for _, id in ipairs(data.ids or {}) do
        if id and id:match("^[a-zA-Z0-9_-]+$") then
            local args = {"/usr/lib/ddns/update.sh", id}
            local exit = nixio.fork()
            
            if exit == 0 then
                nixio.chdir("/")
                nixio.dup(nixio.open("/dev/null", "w")), nixio.stderr)
                nixio.dup(nixio.open("/dev/null", "w")), nixio.stdout)
                nixio.exec(unpack(args))
                os.exit(1)
            elseif exit > 0 then
                local _, status = nixio.wait(exit)
                if nixio.orexitstatus(status) == 0 then
                    results.success = results.success + 1
                    logger.info(id, "Domain updated successfully")
                else
                    results.failed = results.failed + 1
                    logger.error(id, "Domain update failed")
                end
            else
                results.failed = results.failed + 1
                logger.error(id, "Failed to fork process for update")
            end
        else
            results.failed = results.failed + 1
            logger.error("global", "Invalid domain ID in bulk_update_domains: " .. tostring(id))
        end
    end
    
    logger.info("global", string.format("Bulk update completed: %d succeeded, %d failed", results.success, results.failed))
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(results)
end

-- 切换域名启用状态函数
    local data
    local success, err = pcall(function()
        data = json.parse(luci.http.content())
    end)
    
    if not success then
        logger.error("global", "Invalid JSON format in toggle_domain_enable: " .. err)
        return errors.bad_request("Invalid JSON format: " .. err)
    end
    
    if not data.id or not (data.enabled == "0" or data.enabled == "1") then
        logger.error("global", "Invalid parameters in toggle_domain_enable")
        return errors.bad_request("Invalid parameters: id and enabled (0 or 1) are required")
    end
    
    if not data.id:match("^[a-zA-Z0-9_-]+$") then
        logger.error("global", "Invalid domain ID format in toggle_domain_enable: " .. tostring(data.id))
        return errors.bad_request("Invalid domain ID format")
    end
    
    local result = {success = true}
    local commit_success, commit_err = pcall(function()
        uci:set("domain", data.id, "enabled", data.enabled)
        uci:commit("domain")
    end)
    
    if not commit_success then
        logger.error("global", "Failed to save configuration in toggle_domain_enable: " .. commit_err)
        return errors.internal_server_error("Failed to save configuration: " .. commit_err)
    end
    
    logger.info(data.id, "Domain enabled state toggled to " .. data.enabled)
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 删除域名配置函数
    local id = luci.dispatcher.context.path[5]
    
    if not id then
        logger.error("global", "Domain ID is required in delete_domain_config")
        return errors.bad_request("Domain ID is required")
    end
    
    if not id:match("^[a-zA-Z0-9_-]+$") then
        logger.error("global", "Invalid domain ID format in delete_domain_config: " .. tostring(id))
        return errors.bad_request("Invalid domain ID format")
    end
    
    local result = {success = true}
    
    local commit_success, commit_err = pcall(function()
        uci:delete("domain", id)
        uci:commit("domain")
    end)
    
    if not commit_success then
        logger.error("global", "Failed to delete configuration in delete_domain_config: " .. commit_err)
        return errors.internal_server_error("Failed to delete configuration: " .. commit_err)
    end
    
    -- ?
    local log_file = string.format("/var/log/ddns_%s.log", id)
    local status_file = string.format("/tmp/ddns_%s.status", id)
    
    if log_file:match("^/var/log/ddns_.+%.log$") then
        fs.unlink(log_file)
        logger.debug(id, "Deleted log file: " .. log_file)
    end
    
    if status_file:match("^/tmp/ddns_.+%.status$") then
        fs.unlink(status_file)
        logger.debug(id, "Deleted status file: " .. status_file)
    end
    
    logger.info(id, "Domain configuration deleted")
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end
