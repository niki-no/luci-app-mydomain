-- 发送错误响应函数domain/errors.lua - 错误处理模块
module("luci.controller.domain.errors", package.seeall)

-- 
function send_error(http_code, message, error_details)
    local result = {
        success = false,
        message = message or "An error occurred",
        error = error_details
    }
    
    luci.http.status(http_code)
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 发送400错误响应函数
    send_error(400, message or "Bad request")
end

-- 发送401错误响应函数
    send_error(401, message or "Unauthorized")
end

-- 发送403错误响应函数
    send_error(403, message or "Forbidden")
end

-- 发送404错误响应函数
    send_error(404, message or "Resource not found")
end

-- 发送500错误响应函数
    send_error(500, message or "Internal server error", error_details)
end

-- 错误处理包装函数
    return function(...) 
        local ok, err = pcall(func, ...)
        if not ok then
            local sys = require "luci.sys"
            syslog.err("domain API Error: " .. err)
            internal_server_error("An unexpected error occurred", err)
        end
    end
end
