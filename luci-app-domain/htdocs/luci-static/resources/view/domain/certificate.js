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
                        certs.push(f);
                    }
                }
                return certs;
            }),
            L.resolveDefault(fs.exec_direct('/usr/libexec/acmesh-dnsinfo.sh'), ''),
            L.resolveDefault(fs.list('/usr/lib/acme/client/dnsapi/'), null),
            L.resolveDefault(fs.lines('/proc/sys/kernel/hostname'), ''),
            L.resolveDefault(uci.load('ddns')),
        ]);
    },

    render(data) {
        let certs = data[0];
        let dnsApiInfoText = data[1];
        let hasDnsApi = data[2] != null;
        let hostname = data[3];
        let systemDomain = _guessDomain(hostname);
        let ddnsDomains = _collectDdnsDomains();
        let wikiUrl = 'https://github.com/acmesh-official/acme.sh/wiki/';
        let wikiInstructionUrl = wikiUrl + 'dnsapi';
        let m, s, o;

        m = new form.Map("acme", _("证书设置"),
            _("配置ACME (Letsencrypt)自动证书安装。填写配置后，路由器将自动获取并安装Letsencrypt颁发的证书。" +
                "注意：证书中的域名必须已经配置为指向路由器的公网IP地址。" +
                "配置完成后，颁发证书可能需要一段时间。请查看日志了解进度和任何错误。") + '<br/>' +
                _("证书文件存储在") + ' <em>/etc/ssl/acme</em>'+ '<br />' +
                '<a href="https://openwrt.org/docs/guide-user/services/tls/acmesh" target="_blank">' + _('查看更多') + '</a>'
        );

        s = m.section(form.TypedSection, "acme", _("ACME全局配置"));
        s.anonymous = true;

        o = s.option(form.Value, "account_email", _("账户邮箱"),
            _('关联账户密钥的电子邮件地址。') + '<br/>' +
            _('如果证书未及时更新，您将在到期前20天收到通知。')
        );
        o.rmempty = false;
        o.datatype = "minlength(1)";

        o = s.option(form.Flag, "debug", _("启用调试日志"));
        o.rmempty = false;

        if (ddnsDomains && ddnsDomains.length > 0) {
            let ddnsDomainsList = ddnsDomains.map(d => d.domains[0]);
            o = s.option(form.Button, '_import_ddns');
            o.title = _('发现DDNS域名');
            o.inputtitle = _('导入') + ': ' + ddnsDomainsList.join();
            o.inputstyle = 'apply';
            o.onclick = function () {
                _importDdns(ddnsDomains);
            };
        }

        s = m.section(form.GridSection, "cert", _("证书配置"));
        s.anonymous = false;
        s.addremove = true;
        s.nodescriptions = true;

        o = s.tab("general", _("基本设置"));
        o = s.tab('challenge_webroot', _('Webroot验证'));
        o = s.tab('challenge_dns', _('DNS验证'));
        o = s.tab("advanced", _('高级设置'));

        o = s.taboption('general', form.Flag, "enabled", _("启用"));
        o.rmempty = false;

        o = s.taboption('general', form.ListValue, 'validation_method', _('验证方法'),
            _('Standalone模式将使用acme.sh内置的Web服务器颁发证书。' +
                'Webroot模式将使用现有的Web服务器颁发证书。' +
                'DNS模式将允许您使用DNS提供商的DNS API颁发证书。') + '<br />' +
            _('TLS ALPN验证') + ': ' + _('通过TLS端口443验证。') + '<br />' +
            '<a href="https://letsencrypt.org/docs/challenge-types/" target="_blank">' + _('查看更多') + '</a>'
        );
        o.value('standalone', 'HTTP-01 ' + _('Standalone'));
        o.value('webroot', 'HTTP-01 ' + _('Webroot验证'));
        o.value('dns', 'DNS-01 ' + _('DNS验证'));
        o.value('alpn', 'TLS-ALPN-01 ' + _('TLS ALPN验证'));
        o.default = 'standalone';

        if (!hasDnsApi) {
            let dnsApiPkg = 'acme-acmesh-dnsapi';
            o = s.taboption('general', form.Button, '_install');
            o.depends('validation_method', 'dns');
            o.title = _('未安装DNS API包');
            o.inputtitle = _('安装包 %s').format(dnsApiPkg);
            o.inputstyle = 'apply';
            o.onclick = function () {
                let link = L.url('admin/system/package-manager') + '?query=' + dnsApiPkg;
                window.open(link, '_blank', 'noopener');
            };
        }

        o = s.taboption('general', form.Value, 'listen_port', _('监听端口'),
            _('监听ACME挑战请求的端口。验证期间将临时打开该端口。') + '<br />' +
            _('如果您的Web服务器位于反向代理后面并使用不同的端口，可能需要更改。') + '<br />' +
            _('Standalone') + ': ' + _('默认') + ' 80.' + '<br />' +
            _('Webroot验证') + ': ' + _('要临时打开端口，您可以指定Web服务器端口，例如80。') + '<br />' +
            _('TLS ALPN验证') + ': ' + _('默认') + ' 443.'
        );
        o.optional = true;
        o.placeholder = '80';
        o.depends('validation_method', 'standalone');
        o.depends('validation_method', 'webroot');
        o.depends('validation_method', 'alpn');
        o.modalonly = true;

        o = s.taboption('general', form.DynamicList, "domains", _("域名"),
            _("要包含在证书中的域名。" +
                "第一个名称将是主题名称，后续名称将是备用名称。" +
                "注意：证书中的所有域名必须已在全局DNS中解析到路由器。"));
        o.datatype = "list(string)";
        if (systemDomain) {
            o.default = [systemDomain];
        }
        o.validate = function (section_id, value) {
            if (!value) {
                return true;
            }
            if (!/^[*a-z0-9][a-z0-9.-]*$/.test(value)) {
                return _('无效域名。允许小写a-z、数字和连字符-');
            }
            if (value.startsWith('*')) {
                let method = this.section.children.filter(function (o) { return o.option == 'validation_method'; })[0].formvalue(section_id);
                if (method && method !== 'dns') {
                    return _('通配符*需要验证方法：DNS');
                }
            }
            return true;
        };

        o = s.taboption('challenge_webroot', form.Value, 'webroot', _('Webroot目录'),
            _("Web服务器根目录。将其设置为Web服务器" +
                "文档根目录，以Webroot模式运行Acme。Web" +
                "服务器必须在端口80上可从互联网访问。") + '<br/>' +
            _("默认") + " <em>/var/run/acme/challenge/</em>"
        );
        o.optional = true;
        o.depends("validation_method", "webroot");
        o.modalonly = true;

        o = s.taboption('challenge_dns', form.ListValue, 'dns', _('DNS API'),
            _("要使用DNS模式颁发证书，请将其设置为acme.sh支持的DNS API名称。" +
                "有关可用API的列表，请参阅https://github.com/acmesh-official/acme.sh/wiki/dnsapi。" +
                "在DNS模式下，域名不必解析到路由器IP。" +
                "DNS模式也是唯一支持通配符证书的模式。" +
                "使用此模式需要安装acme-dnsapi包。"));
        o.depends("validation_method", "dns");
        o.value('', _('请选择DNS API'));
        o.value('dns_cf', _('Cloudflare'));
        o.value('dns_ali', _('阿里云'));
        o.value('dns_dp', _('腾讯云'));
        o.value('dns_aws', _('AWS Route53'));
        o.value('dns_gd', _('Godaddy'));
        o.value('dns_namesilo', _('Namesilo'));
        o.value('dns_cloudns', _('ClouDNS'));
        o.value('dns_dynu', _('Dynu'));
        o.value('dns_he', _('Hurricane Electric'));
        o.value('dns_inwx', _('INWX'));
        o.value('dns_ionos', _('IONOS'));
        o.value('dns_jd', _('京东云'));
        o.value('dns_linode', _('Linode'));
        o.value('dns_namecheap', _('Namecheap'));
        o.value('dns_nsone', _('NS1'));
        o.value('dns_oracle', _('Oracle Cloud'));
        o.value('dns_rackspace', _('Rackspace'));
        o.value('dns_transip', _('TransIP'));
        o.value('dns_vultr', _('Vultr'));
        o.modalonly = true;

        o = s.taboption('challenge_dns', form.DynamicList, 'credentials', _('DNS API凭据'),
            _("上面选择的DNS API模式的凭据。" +
                "有关每个API所需的凭据格式，请参阅https://github.com/acmesh-official/acme.sh/wiki/dnsapi。" +
                "在此处添加多个条目，格式为KEY=VAL shell变量，以提供多个凭据变量。"));
        o.datatype = "list(string)";
        o.depends("validation_method", "dns");
        o.modalonly = true;

        o = s.taboption('challenge_dns', form.Value, 'calias', _('挑战别名'),
            _("用于所有域的挑战别名。" +
                "有关此过程的详细信息，请参阅https://github.com/acmesh-official/acme.sh/wiki/DNS-alias-mode。" +
                "LUCI仅支持每个证书一个挑战别名。"));
        o.depends("validation_method", "dns");
        o.modalonly = true;

        o = s.taboption('challenge_dns', form.Value, 'dalias', _('域别名'),
            _("用于所有域的域别名。" +
                "有关此过程的详细信息，请参阅https://github.com/acmesh-official/acme.sh/wiki/DNS-alias-mode。" +
                "LUCI仅支持每个证书一个域别名。"));
        o.depends("validation_method", "dns");
        o.modalonly = true;

        o = s.taboption('advanced', form.ListValue, 'key_type', _('密钥类型'),
            _('生成证书的密钥大小（和类型）。')
        );
        o.value('rsa2048', _('RSA 2048位'));
        o.value('rsa3072', _('RSA 3072位'));
        o.value('rsa4096', _('RSA 4096位'));
        o.value('ec256', _('ECC 256位'));
        o.value('ec384', _('ECC 384位'));
        o.rmempty = false;
        o.optional = true;
        o.modalonly = true;
        o.cfgvalue = function(section_id) {
            let keylength = uci.get('acme', section_id, 'keylength');
            if (keylength) {
                switch (keylength) {
                    case '2048': return 'rsa2048';
                    case '3072': return 'rsa3072';
                    case '4096': return 'rsa4096';
                    case 'ec-256': return 'ec256';
                    case 'ec-384': return 'ec384';
                    default: return '';
                }
            }
            return this.super('cfgvalue', arguments);
        };
        o.write = function(section_id, value) {
            uci.unset('acme', section_id, 'keylength');
            uci.set('acme', section_id, 'key_type', value);
        };

        o = s.taboption('advanced', form.Value, "acme_server", _("ACME服务器URL"),
            _('使用自定义CA而不是Let\'s Encrypt。') + ' ' + _('自定义ACME服务器目录URL。') + '<br />' +
            '<a href="https://github.com/acmesh-official/acme.sh/wiki/Server" target="_blank">' + _('查看更多') + '</a>' + '<br />'
            + _('默认') + ' <code>letsencrypt</code>'
        );
        o.placeholder = "https://api.buypass.com/acme/directory";
        o.optional = true;
        o.modalonly = true;

        o = s.taboption('advanced', form.Flag, 'staging', _('使用测试服务器'),
            _(
                '从Letsencrypt测试服务器获取证书 ' +
                '(用于测试；证书不会有效)。'
            )
        );
        o.depends('acme_server', '');
        o.optional = true;
        o.modalonly = true;

        o = s.taboption('advanced', form.Value, 'days', _('更新前天数'));
        o.optional    = true;
        o.placeholder = 'acme.sh默认值 (60天)';
        o.datatype    = 'uinteger';
        o.modalonly = true;

        s = m.section(form.GridSection, '_certificates');
        s.render = L.bind(_renderCerts, this, certs);

        // 添加日志显示部分
        s = m.section(form.GridSection, '_logs');
        s.render = L.bind(this.renderLogs, this, 'acme');

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

function _isFqdn(domain) {
    let i = domain.lastIndexOf('.');
    if (i < 0) {
        return false;
    }
    let tld = domain.substr(i + 1);
    if (tld.length < 2) {
        return false;
    }
    return /^[a-z0-9]+$/.test(tld);
}

function _guessDomain(hostname) {
    return _isFqdn(hostname) ? hostname : (_isFqdn(window.location.hostname) ? window.location.hostname : '');
}

function _collectDdnsDomains() {
    let ddnsDomains = [];
    let ddnsServices = uci.sections('ddns', 'service');
    for (let ddnsService of ddnsServices) {
        let dnsApi = '';
        let credentials = [];
        switch (ddnsService.service_name) {
            case 'duckdns.org':
                dnsApi = 'dns_duckdns';
                credentials = [
                    'DuckDNS_Token=' + ddnsService['password'],
                ];
                break;
            case 'dynv6.com':
                dnsApi = 'dns_dynv6';
                credentials = [
                    'DYNV6_TOKEN=' + ddnsService['password'],
                ];
                break;
            case 'afraid.org-v2-basic':
                dnsApi = 'dns_freedns';
                credentials = [
                    'FREEDNS_User=' + ddnsService['username'],
                    'FREEDNS_Password=' + ddnsService['password'],
                ];
                break;
            case 'cloudflare.com-v4':
                dnsApi = 'dns_cf';
                credentials = [
                    'CF_Token=' + ddnsService['password'],
                ];
                break;
        }
        if (credentials.length > 0) {
            ddnsDomains.push({
                sectionId: ddnsService['.name'],
                domains: [ddnsService['domain'], ddnsService['domain']],
                dnsApi: dnsApi,
                credentials: credentials,
            });
        }
    }
    return ddnsDomains;
}

function _renderCerts(certs) {
    let table = E('table', {'class': 'table cbi-section-table', 'id': 'certificates_table'}, [
        E('tr', {'class': 'tr table-titles'}, [
            E('th', {'class': 'th'}, _('主域名')),
            E('th', {'class': 'th'}, _('私钥路径')),
            E('th', {'class': 'th'}, _('公钥证书路径')),
            E('th', {'class': 'th'}, _('颁发日期')),
        ])
    ]);

    let rows = certs.map(function (cert) {
        let domain = cert.name.replace(/\.fullchain\.crt$/, '');
        let issueDate = new Date(cert.mtime * 1000).toLocaleDateString();
        return [
            domain,
            '/etc/ssl/acme/' + domain + '.key',
            '/etc/ssl/acme/' + domain + '.fullchain.crt',
            issueDate,
        ];
    });

    cbi_update_table(table, rows);

    return E('div', {'class': 'cbi-section cbi-tblsection'}, [
        E('h3', _('已安装证书')), table]);
}