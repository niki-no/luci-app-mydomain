'use strict';
'require ui';
'require view';

return view.extend({
	render: function() {
		var buttons = [
			{
				name: 'ddns',
				title: _('Dynamic DNS'),
				desc: _('Configure Dynamic DNS for your domains'),
				url: L.url('admin/services/mydomain/ddns')
			},
			{
				name: 'proxy',
				title: _('Reverse Proxy'),
				desc: _('Configure Reverse Proxy with HAProxy'),
				url: L.url('admin/services/mydomain/proxy')
			},
			{
				name: 'cert',
				title: _('Certificate Management'),
				desc: _('Manage SSL/TLS certificates with ACME'),
				url: L.url('admin/services/mydomain/cert')
			},
			{
				name: 'status',
				title: _('Status'),
				desc: _('View status of all services'),
				url: L.url('admin/services/mydomain/status')
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