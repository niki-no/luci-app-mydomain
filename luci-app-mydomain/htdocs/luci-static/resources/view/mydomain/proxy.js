'use strict';
'require view';
'require ui';
'require form';
'require tools.widgets as widgets';

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('mydomain', _('Reverse Proxy Configuration'), 
			_('Configure Reverse Proxy with HAProxy'));

		s = m.section(form.TypedSection, 'proxy', _('Proxy Entries'));
		s.addremove = true;
		s.anonymous = false;

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = '0';

		o = s.option(form.Value, 'name', _('Name'));
		o.rmempty = false;

		o = s.option(form.Value, 'frontend_port', _('Frontend Port'));
		o.datatype = 'port';
		o.rmempty = false;

		o = s.option(form.Value, 'backend_url', _('Backend URL'));
		o.datatype = 'hostport';
		o.rmempty = false;

		o = s.option(form.ListValue, 'protocol', _('Protocol'));
		o.value('http', 'HTTP');
		o.value('https', 'HTTPS');
		o.value('tcp', 'TCP');
		o.value('websocket', 'WebSocket');
		o.default = 'http';

		o = s.option(form.Value, 'cert', _('SSL Certificate'));
		o.depends('protocol', 'https');
		// 获取证书配置
		L.resolveDefault(LFS.list('/etc/ssl/certs/')).then(function(files) {
			if (files) {
				files.forEach(function(file) {
					if (file.name && file.name.endsWith('.crt')) {
						o.value(file.name.replace('.crt', ''), file.name);
					}
				});
			}
		});

		o = s.option(form.DynamicList, 'acl_rules', _('ACL Rules'));
		o.depends('protocol', 'http');
		o.depends('protocol', 'https');

		o = s.option(form.ListValue, 'lb_algorithm', _('Load Balancing Algorithm'));
		o.value('roundrobin', 'Round Robin');
		o.value('static-rr', 'Static Round Robin');
		o.value('leastconn', 'Least Connections');
		o.value('source', 'Source');
		o.default = 'roundrobin';

		o = s.option(form.Flag, 'health_check', _('Enable Health Check'));
		o.default = '1';

		o = s.option(form.Value, 'health_check_url', _('Health Check URL'));
		o.depends('health_check', '1');
		o.placeholder = '/health';

		return m.render();
	}
});
