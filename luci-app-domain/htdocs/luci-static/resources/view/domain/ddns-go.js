/*   Copyright (C) 2021-2025 sirpdboy herboy2008@gmail.com https://github.com/sirpdboy/luci-app-domain */
'use strict';
'require view';
'require fs';
'require ui';
'require uci';
'require form';
'require poll';

function checkProcess() {
    // 先尝试用 pidof
    try {
        return fs.exec('/bin/pidof', ['ddns-go']).then(function(pidofRes) {
            if (pidofRes.code === 0) {
                return {
                    running: true,
                    pid: pidofRes.stdout.trim()
                };
            }
            // 尝试用 ps
            return fs.exec('/bin/ps', ['-C', 'ddns-go', '-o', 'pid=']).then(function(psRes) {
                const pid = psRes.stdout.trim();
                return {
                    running: pid !== '',
                    pid: pid || null
                };
            });
        });
    } catch (err) {
        return Promise.resolve({ running: false, pid: null });
    }
}

function renderStatus(isRunning, listen_port, noweb, version) {
    var statusText = isRunning ? _('运行中') : _('未运行');
    var color = isRunning ? 'green' : 'red';
    var icon = isRunning ? '✓' : '✗';
    var versionText = version ? `v${version}` : '';
    
    var html = String.format(
        '<em><span style="color:%s">%s <strong>%s %s - %s</strong></span></em>',
        color, icon, _('DDNS-Go'), versionText, statusText
    );
    
    return html;
}

return view.extend({
    load: function() {
        return uci.load('ddns-go');
    },

    checkRunning: function() {
        return fs.exec('/bin/pidof', ['ddns-go']).then(function(pidRes) {
            if (pidRes.code === 0) return { isRunning: true };
            return fs.exec('/bin/ash', ['-c', 'ps | grep -q "[d]dns-go"']).then(function(grepRes) {
                return { isRunning: grepRes.code === 0 };
            });
        });
    },
    
    render: function() {
        var m, s, o;

        m = new form.Map('ddns-go', _('动态域名'),
            _('动态域名服务自动获取您的公网IPv4或IPv6地址，并解析到对应的域名服务。'));

        // 基本设置和控制面板部分 - 参考反代设置的页面样式
        s = m.section(form.GridSection, 'config', _('动态域名配置'));
        s.anonymous = false;
        s.addremove = false;
        s.nodescriptions = true;

        o = s.tab('basic', _('基本设置'));
        o = s.tab('control', _('控制面板'));
        o = s.tab('logs', _('运行日志'));

        // 基本设置选项卡
        o = s.taboption('basic', form.Flag, 'enabled', _('启用'));
        o.default = o.disabled;
        o.rmempty = false;

        o = s.taboption('basic', form.Value, 'time', _('更新间隔'));
        o.default = '300';

        o = s.taboption('basic', form.Value, 'ctimes', _('与服务提供商比较次数间隔'));
        o.default = '5';

        o = s.taboption('basic', form.Value, 'skipverify', _('跳过证书验证'));
        o.default = '0';

        o = s.taboption('basic', form.Value, 'dns', _('指定DNS解析服务器'));
        o.value('223.5.5.5', _('阿里DNS 223.5.5.5'));
        o.value('223.6.6.6', _('阿里DNS 223.6.6.6'));
        o.value('119.29.29.29', _('腾讯DNS 119.29.29.29'));
        o.value('1.1.1.1', _('CloudFlare DNS 1.1.1.1'));
        o.value('8.8.8.8', _('谷歌DNS 8.8.8.8'));
        o.value('8.8.4.4', _('谷歌DNS 8.8.4.4'));
        o.datatype = 'ipaddr'; 

        o = s.taboption('basic', form.Value, 'delay', _('延迟启动 (秒)'));
        o.default = '60';

        // 控制面板选项卡
        s.taboption('control', form.DummyValue, '_control_panel', _('服务状态')).render = function() {
            var statusView = E('p', { id: 'control_status' }, 
                '<span class="spinning"></span> ' + _('检查状态中...'));
            
            window.statusPoll = function() {
                return checkProcess().then(function(processInfo) {
                    statusView.innerHTML = renderStatus(processInfo.running, '', '', '');
                }).catch(function(err) {
                    console.error('Status check failed:', err);
                    statusView.innerHTML = '<span style="color:orange">⚠ ' + _('状态检查错误') + '</span>';
                });
            };
            
            var pollInterval = poll.add(window.statusPoll, 5); // 每5秒检查一次
            
            return E('div', { class: 'cbi-section', id: 'status_bar' }, [
                statusView,
                E('div', { 'style': 'text-align: right; font-style: italic;' }, [
                    E('span', {}, [
                        _('© github '),
                        E('a', { 
                            'href': 'https://github.com/sirpdboy', 
                            'target': '_blank',
                            'style': 'text-decoration: none;'
                        }, 'by sirpdboy')
                    ])
                ])
            ]);
        };

        // 运行日志选项卡
        s.taboption('logs', form.DummyValue, '_logs', _('运行日志')).render = L.bind(this.renderLogs, this, 'ddns-go');

        return m.render();
    },

    renderLogs: function(service) {
        var logContainer = E('div', { class: 'cbi-section', style: 'margin-top: 10px;' }, [
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
                    // 只保留最新的100条日志
                    var lines = res.stdout.split('\n');
                    if (lines.length > 100) {
                        lines = lines.slice(-100);
                    }
                    logContent.textContent = lines.join('\n');
                } else {
                    logContent.textContent = _('无法获取日志: ') + (res.stderr || res.stdout);
                }
            })
            .catch(function(err) {
                logContent.textContent = _('错误: ') + err.message;
            });
    },

    clearLogs: function(service) {
        return fs.exec('/bin/ash', ['-c', 'logread -c || echo \"不支持清除日志\"'])
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