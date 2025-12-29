'use strict';
'require form';
'require fs';
'require uci';
'require ui';
'require view';
'require poll';

return view.extend({
    load() {
        return Promise.all([
            L.resolveDefault(fs.list('/etc/ssl/acme/'), []).then(files => {
                let certs = [];
                for (let f of files) {
                    if (f.name.match(/\.fullchain\.crt$/)) {
                        certs.push(f.name.replace(/\.fullchain\.crt$/, ''));
                    }
                }
                return certs;
            }),
            uci.load('haproxy'),
        ]);
    },

    render(data) {
        let certs = data[0];
        let m, s, o;

        m = new form.Map("haproxy", _("反代设置"),
            _("配置HAProxy反向代理服务。使用此功能可以将外部请求转发到内部服务器。") + '<br/>' +
            _("您可以选择证书设置中申请的证书来为相关域名启用HTTPS。")
        );

        s = m.section(form.TypedSection, "global", _("全局配置"));
        s.anonymous = true;

        o = s.option(form.Flag, "enabled", _("启用HAProxy"));
        o.default = o.disabled;
        o.rmempty = false;

        o = s.option(form.Value, "maxconn", _("最大连接数"));
        o.default = "1000";
        o.datatype = "uinteger";
        o.rmempty = false;

        o = s.option(form.Value, "timeout_connect", _("连接超时"));
        o.default = "5000";
        o.datatype = "uinteger";
        o.rmempty = false;

        o = s.option(form.Value, "timeout_client", _("客户端超时"));
        o.default = "50000";
        o.datatype = "uinteger";
        o.rmempty = false;

        o = s.option(form.Value, "timeout_server", _("服务器超时"));
        o.default = "50000";
        o.datatype = "uinteger";
        o.rmempty = false;

        s = m.section(form.GridSection, "listen", _("监听配置"));
        s.anonymous = false;
        s.addremove = true;
        s.nodescriptions = true;

        o = s.tab("general", _("基本设置"));
        o = s.tab("backend", _("后端服务器"));
        o = s.tab("ssl", _("SSL设置"));

        o = s.taboption("general", form.Flag, "enabled", _("启用"));
        o.rmempty = false;

        o = s.taboption("general", form.Value, "bind", _("监听地址和端口"),
            _("格式：[ip]:port，例如：0.0.0.0:80 或 [::]:443")
        );
        o.default = "0.0.0.0:80";
        o.rmempty = false;

        o = s.taboption("general", form.ListValue, "mode", _("模式"));
        o.value("http", _("HTTP"));
        o.value("https", _("HTTPS"));
        o.value("tcp", _("TCP"));
        o.default = "http";
        o.rmempty = false;

        o = s.taboption("general", form.DynamicList, "acl", _("访问控制列表"),
            _("格式：acl name type condition，例如：acl is_www hdr(host) -i www.example.com")
        );
        o.datatype = "string";
        o.modalonly = true;

        o = s.taboption("general", form.DynamicList, "use_backend", _("使用后端"),
            _("格式：use_backend backend_name if acl_name，例如：use_backend www_backend if is_www")
        );
        o.datatype = "string";
        o.modalonly = true;

        o = s.taboption("backend", form.Value, "backend_name", _("后端名称"),
            _("唯一标识此后端服务器组")
        );
        o.default = "backend1";
        o.rmempty = false;

        o = s.taboption("backend", form.DynamicList, "server", _("后端服务器"),
            _("格式：server name ip:port [options]，例如：server server1 192.168.1.100:80 check")
        );
        o.datatype = "string";
        o.rmempty = false;
        o.modalonly = true;

        o = s.taboption("backend", form.Value, "balance", _("负载均衡算法"));
        o.value("roundrobin", _("轮询"));
        o.value("leastconn", _("最少连接"));
        o.value("source", _("源IP哈希"));
        o.default = "roundrobin";
        o.rmempty = false;

        o = s.taboption("ssl", form.Flag, "ssl_enabled", _("启用SSL"));
        o.default = o.disabled;

        o = s.taboption("ssl", form.ListValue, "certificate", _("选择证书"),
            _("从证书设置中选择已申请的证书")
        );
        o.depends("ssl_enabled", "1");
        o.value("", _("无"));
        
        certs.forEach(function(cert) {
            o.value(cert, cert);
        });
        
        o.modalonly = true;
        o.onchange = function(section_id, value) {
            if (value) {
                uci.set('haproxy', section_id, 'ssl_cert', '/etc/ssl/acme/' + value + '.fullchain.crt');
                uci.set('haproxy', section_id, 'ssl_key', '/etc/ssl/acme/' + value + '.key');
            } else {
                uci.unset('haproxy', section_id, 'ssl_cert');
                uci.unset('haproxy', section_id, 'ssl_key');
            }
        };

        o = s.taboption("ssl", form.Value, "ssl_cert", _("证书文件路径"),
            _("SSL证书文件的完整路径")
        );
        o.depends("ssl_enabled", "1");
        o.placeholder = "/etc/ssl/acme/example.com.fullchain.crt";
        o.modalonly = true;

        o = s.taboption("ssl", form.Value, "ssl_key", _("私钥文件路径"),
            _("SSL私钥文件的完整路径")
        );
        o.depends("ssl_enabled", "1");
        o.placeholder = "/etc/ssl/acme/example.com.key";
        o.modalonly = true;

        o = s.taboption("ssl", form.Flag, "ssl_redirect", _("HTTP重定向到HTTPS"),
            _("将HTTP请求自动重定向到HTTPS")
        );
        o.depends("ssl_enabled", "1");
        o.default = o.disabled;

        // 添加日志显示部分
        s = m.section(form.GridSection, '_logs');
        s.render = L.bind(this.renderLogs, this, 'haproxy');

        return m.render();
    },

    renderLogs: function(service) {
        var logContainer = E('div', { class: 'cbi-section', style: 'margin-top: 20px;' }, [
            E('h3', _('运行日志')),
            E('div', { style: 'margin-bottom: 10px;' }, [
                E('button', {
                    class: 'cbi-button',
                    click: L.bind(this.refreshLogs, this, service)
                }, _('刷新日志')),
                E('button', {
                    class: 'cbi-button',
                    click: L.bind(this.clearLogs, this, service)
                }, _('清除日志'))
            ]),
            E('pre', {
                id: service + '_log_content',
                style: 'background: #000; color: #eee; padding: 10px; height: 300px; overflow: auto; font-family: monospace; font-size: 12px; white-space: pre-wrap; word-wrap: break-word;'
            }, _('加载日志中...'))
        ]);

        this.refreshLogs(service);

        poll.add(L.bind(this.refreshLogs, this, service), 5);
        poll.start();

        return logContainer;
    },

    refreshLogs: function(service) {
        var logContent = document.getElementById(service + '_log_content');
        var logCommand;

        switch(service) {
            case 'haproxy':
                logCommand = '/bin/ash -c "logread -e haproxy || cat /var/log/haproxy.log 2>/dev/null || echo \"No HAProxy logs found\""';
                break;
            case 'acme':
                logCommand = '/bin/ash -c "logread -e acme || cat /var/log/acme.log 2>/dev/null || echo \"No ACME logs found\""';
                break;
            case 'ddns-go':
                logCommand = '/bin/ash -c "logread -e ddns-go || cat /var/log/ddns-go.log 2>/dev/null || echo \"No DDNS-GO logs found\""';
                break;
            default:
                logCommand = '/bin/ash -c "echo \"Unknown service logs\""';
        }

        return fs.exec('/bin/ash', ['-c', logCommand])
            .then(function(res) {
                if (res.code === 0) {
                    logContent.textContent = res.stdout;
                } else {
                    logContent.textContent = _('无法获取日志: ') + (res.stderr || res.stdout);
                }
            })
            .catch(function(err) {
                logContent.textContent = _('错误: ') + err.message;
            });
    },

    clearLogs: function(service) {
        return fs.exec('/bin/ash', ['-c', 'logread -c || echo "不支持清除日志"'])
            .then(function(res) {
                if (res.code === 0) {
                    this.refreshLogs(service);
                } else {
                    alert(_('无法清除日志: ') + (res.stderr || res.stdout));
                }
            }.bind(this))
            .catch(function(err) {
                alert(_('错误: ') + err.message);
            });
    }
});