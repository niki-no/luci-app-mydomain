module("luci.controller.mydomain", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/mydomain") then
		return
	end

	local page = entry({"admin", "services", "mydomain"}, alias("admin", "services", "mydomain", "ddns"), _("MyDomain Manager"), 60)
	page.dependent = false
	page.acl_depends = { "luci-app-mydomain" }

	entry({"admin", "services", "mydomain", "ddns"}, cbi("mydomain/ddns"), _("Dynamic DNS"), 10).leaf = true
	entry({"admin", "services", "mydomain", "proxy"}, cbi("mydomain/proxy"), _("Reverse Proxy"), 20).leaf = true
	entry({"admin", "services", "mydomain", "cert"}, cbi("mydomain/cert"), _("Certificate Management"), 30).leaf = true
	entry({"admin", "services", "mydomain", "status"}, call("action_status"), _("Status"), 40).leaf = true
end

function action_status()
	local uci = luci.model.uci.cursor()
	local data = {}

	-- Get DDNS status
	local ddns_status = {}
	uci:foreach("mydomain", "ddns", function(s)
		local name = s[".name"]
		local enabled = s.enabled or "0"
		local domain = s.domain or ""
		local status = "unknown"
		
		if enabled == "1" then
			local last_update = nixio.fs.readfile("/tmp/mydomain_ddns_" .. name .. ".log")
			if last_update then
				status = "active"
			else
				status = "inactive"
			end
		else
			status = "disabled"
		end
		
		table.insert(ddns_status, {
			name = name,
			domain = domain,
			status = status,
			enabled = enabled
		})
	end)
	
	data.ddns = ddns_status
	
	-- Get proxy status
	local proxy_status = {}
	uci:foreach("mydomain", "proxy", function(s)
		local name = s[".name"]
		local enabled = s.enabled or "0"
		local frontend = s.frontend_port or ""
		local backend = s.backend_url or ""
		
		table.insert(proxy_status, {
			name = name,
			frontend = frontend,
			backend = backend,
			enabled = enabled
		})
	end)
	
	data.proxy = proxy_status
	
	-- Get certificate status
	local cert_status = {}
	uci:foreach("mydomain", "certificate", function(s)
		local name = s[".name"]
		local domain = s.domain or ""
		local cert_path = s.cert_path or ""
		local status = "unknown"
		
		if nixio.fs.access(cert_path) then
			local stat = nixio.fs.stat(cert_path)
			if stat then
				status = os.date("%Y-%m-%d %H:%M:%S", stat.mtime)
			else
				status = "valid"
			end
		else
			status = "missing"
		end
		
		table.insert(cert_status, {
			name = name,
			domain = domain,
			status = status
		})
	end)
	
	data.cert = cert_status
	
	luci.template.render("mydomain/status", {data=data})
end