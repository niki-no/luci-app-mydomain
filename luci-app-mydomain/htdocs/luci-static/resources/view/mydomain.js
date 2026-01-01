'use strict';
'require ui';
'require view';
'require util';
'require i18n';
'require fs';

return view.extend({
	render: function() {
		// Helper function to build URLs
		function buildUrl(path) {
			var parts = path.split('/');
			return '/cgi-bin/luci/admin/services/mydomain/' + parts[parts.length - 1];
		}
		
		var buttons = [
			{
				name: 'ddns',
				title: _('Dynamic DNS'),
				desc: _('Configure Dynamic DNS for your domains'),
				url: buildUrl('admin/services/mydomain/ddns')
			},
			{
				name: 'proxy',
				title: _('Reverse Proxy'),
				desc: _('Configure Reverse Proxy with HAProxy'),
				url: buildUrl('admin/services/mydomain/proxy')
			},
			{
				name: 'cert',
				title: _('Certificate Management'),
				desc: _('Manage SSL/TLS certificates with ACME'),
				url: buildUrl('admin/services/mydomain/cert')
			},
			{
				name: 'status',
				title: _('Status'),
				desc: _('View status of all services'),
				url: buildUrl('admin/services/mydomain/status')
			}
		];

		var content = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('MyDomain Manager')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('Manage your domain services including Dynamic DNS, Reverse Proxy and Certificate Management.'))
			])
		]);

		buttons.forEach(function(btn) {
			content.appendChild(E('div', { 'class': 'cbi-section-node' }, [
				E('div', { 'class': 'table' }, [
					E('div', { 'class': 'tr' }, [
						E('div', { 'class': 'td left' }, [
							E('strong', {}, btn.title),
							E('br'),
							E('small', { 'class': 'cbi-option-desc' }, btn.desc)
						]),
						E('div', { 'class': 'td right' }, [
							E('button', {
								'class': 'btn cbi-button cbi-button-action',
								'click': ui.createHandlerFn(this, 'show', btn.url)
							}, _('Open'))
						])
					])
				])
			]));
		});

		return content;
	},

	show: function(url) {
		location.href = url;
	}
});
