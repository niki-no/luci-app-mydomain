/**
 * domain Enhanced JavaScript
 * Copyright (c) 2026 domain Maintainers
 * Licensed under the Apache License 2.0
 */

(function() {
    'use strict';
    
    // 全局domain对象
    window.domain = window.domain || {};
    
    // 配置
    const CONFIG = {
        apiBase: '<%= url("admin/services/domain/api") %>',
        refreshInterval: 30000,
        version: '1.0.0'
    };
    
    // 工具函数
    const Utils = {
        // AJAX请求
        ajax: function(url, options = {}) {
            const defaults = {
                method: 'GET',
                headers: {
                    'Content-Type': 'application/json',
                    'X-Requested-With': 'XMLHttpRequest'
                }
            };
            
            const config = { ...defaults, ...options };
            
            // 添加CSRF令牌
            const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
            if (csrfToken) {
                config.headers['X-CSRF-Token'] = csrfToken;
            }
            
            if (config.body && typeof config.body === 'object') {
                config.body = JSON.stringify(config.body);
            }
            
            return fetch(url, config)
                .then(response => {
                    if (!response.ok) {
                        throw new Error(`HTTP ${response.status}`);
                    }
                    return response.json();
                })
                .catch(error => {
                    console.error('AJAX Error:', error);
                    throw error;
                });
        },
        
        // 格式化时间
        formatTime: function(date) {
            if (!date) return '-';
            const d = new Date(date);
            return d.toLocaleString();
        },
        
        // 相对时间
        relativeTime: function(date) {
            const now = new Date();
            const target = new Date(date);
            const diff = now - target;
            
            const minutes = Math.floor(diff / 60000);
            const hours = Math.floor(minutes / 60);
            const days = Math.floor(hours / 24);
            
            if (days > 0) {
                return days === 1 ? '1 day ago' : `${days} days ago`;
            } else if (hours > 0) {
                return hours === 1 ? '1 hour ago' : `${hours} hours ago`;
            } else if (minutes > 0) {
                return minutes === 1 ? '1 minute ago' : `${minutes} minutes ago`;
            } else {
                return 'Just now';
            }
        },
        
        // 显示通知
        showNotification: function(message, type = 'info') {
            const notification = document.createElement('div');
            notification.className = `domain-alert domain-alert-${type}`;
            notification.innerHTML = `
                <i class="icon icon-${this.getNotificationIcon(type)}"></i>
                <div class="domain-alert-content">
                    ${message}
                </div>
            `;
            
            // 添加到页面
            const container = document.querySelector('.domain-container') || document.body;
            container.appendChild(notification);
            
            // 自动移除
            setTimeout(() => {
                notification.classList.add('fade-out');
                setTimeout(() => notification.remove(), 300);
            }, 5000);
        },
        
        // 获取通知图标
        getNotificationIcon: function(type) {
            switch (type) {
                case 'success': return 'check';
                case 'error': return 'warning';
                case 'warning': return 'alert';
                default: return 'info';
            }
        },
        
        // 确认对话框
        confirm: function(message) {
            return new Promise((resolve) => {
                const modal = this.createModal({
                    title: 'Confirm',
                    content: `<p>${message}</p>`,
                    buttons: [
                        {
                            text: 'Cancel',
                            type: 'secondary',
                            onClick: () => {
                                modal.close();
                                resolve(false);
                            }
                        },
                        {
                            text: 'OK',
                            type: 'primary',
                            onClick: () => {
                                modal.close();
                                resolve(true);
                            }
                        }
                    ]
                });
                modal.open();
            });
        },
        
        // 创建模态框
        createModal: function(options) {
            const modal = document.createElement('div');
            modal.className = 'domain-modal';
            
            const buttonsHTML = options.buttons ? options.buttons.map(btn => 
                `<button class="domain-btn domain-btn-${btn.type}" data-action="${btn.action || ''}">${btn.text}</button>`
            ).join('') : '';
            
            modal.innerHTML = `
                <div class="domain-modal-content">
                    <div class="domain-modal-header">
                        <div class="domain-modal-title">${options.title}</div>
                        <button class="domain-modal-close">&times;</button>
                    </div>
                    <div class="domain-modal-body">${options.content}</div>
                    ${options.buttons ? `
                    <div class="domain-modal-footer">
                        ${buttonsHTML}
                    </div>
                    ` : ''}
                </div>
            `;
            
            document.body.appendChild(modal);
            
            const closeBtn = modal.querySelector('.domain-modal-close');
            closeBtn.addEventListener('click', () => modal.close());
            
            modal.addEventListener('click', (e) => {
                if (e.target === modal) {
                    modal.close();
                }
            });
            
            options.buttons?.forEach((btn, index) => {
                const button = modal.querySelectorAll('.domain-modal-footer button')[index];
                button.addEventListener('click', () => {
                    if (btn.onClick) {
                        btn.onClick();
                    }
                    if (btn.close !== false) {
                        modal.close();
                    }
                });
            });
            
            modal.open = function() {
                setTimeout(() => {
                    modal.classList.add('domain-modal-active');
                }, 10);
            };
            
            modal.close = function() {
                modal.classList.remove('domain-modal-active');
                setTimeout(() => {
                    modal.remove();
                }, 300);
            };
            
            return modal;
        },
        
        // 加载指示器
        showLoading: function(element) {
            const loading = document.createElement('div');
            loading.className = 'domain-loading';
            loading.innerHTML = '<i class="icon icon-spinner icon-spin"></i> Loading...';
            
            if (element) {
                element.innerHTML = '';
                element.appendChild(loading);
            }
            
            return loading;
        },
        
        // 格式化字节
        formatBytes: function(bytes, decimals = 2) {
            if (bytes === 0) return '0 Bytes';
            
            const k = 1024;
            const dm = decimals < 0 ? 0 : decimals;
            const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
            
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            
            return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
        }
    };
    
    // 证书管理
    const Certificate = {
        // 检查证书状态
        checkStatus: function(domain) {
            return Utils.ajax(`${CONFIG.apiBase}/cert/status${domain ? `?domain=${domain}` : ''}`)
                .then(data => {
                    if (data.success) {
                        return data.data;
                    } else {
                        throw new Error(data.message);
                    }
                });
        },
        
        // 更新证书
        renew: function(domain) {
            return Utils.ajax(`${CONFIG.apiBase}/cert/renew`, {
                method: 'POST',
                body: domain ? { domain } : {}
            });
        },
        
        // 获取证书列表
        list: function() {
            return Utils.ajax(`${CONFIG.apiBase}/cert/list`);
        },
        
        // 删除证书
        remove: function(domain) {
            return Utils.ajax(`${CONFIG.apiBase}/cert/remove`, {
                method: 'POST',
                body: { domain }
            });
        },
        
        // 生成证书
        generate: function(data) {
            return Utils.ajax(`${CONFIG.apiBase}/cert/generate`, {
                method: 'POST',
                body: data
            });
        },
        
        // 验证证书
        verify: function(domain) {
            return Utils.ajax(`${CONFIG.apiBase}/cert/verify${domain ? `?domain=${domain}` : ''}`);
        }
    };
    
    // DNS管理
    const DNS = {
        // 获取DNS记录
        getRecords: function(domain) {
            return Utils.ajax(`${CONFIG.apiBase}/dns/records${domain ? `?domain=${domain}` : ''}`);
        },
        
        // 添加DNS记录
        addRecord: function(record) {
            return Utils.ajax(`${CONFIG.apiBase}/dns/add`, {
                method: 'POST',
                body: record
            });
        },
        
        // 更新DNS记录
        updateRecord: function(record) {
            return Utils.ajax(`${CONFIG.apiBase}/dns/update`, {
                method: 'POST',
                body: record
            });
        },
        
        // 删除DNS记录
        deleteRecord: function(id) {
            return Utils.ajax(`${CONFIG.apiBase}/dns/delete`, {
                method: 'POST',
                body: { id }
            });
        },
        
        // 检查DNS传播
        checkPropagation: function(domain) {
            return Utils.ajax(`${CONFIG.apiBase}/dns/propagation${domain ? `?domain=${domain}` : ''}`);
        }
    };
    
    // 代理管理
    const Proxy = {
        // 获取代理状态
        getStatus: function() {
            return Utils.ajax(`${CONFIG.apiBase}/proxy/status`);
        },
        
        // 启动代理
        start: function() {
            return Utils.ajax(`${CONFIG.apiBase}/proxy/start`, {
                method: 'POST'
            });
        },
        
        // 停止代理
        stop: function() {
            return Utils.ajax(`${CONFIG.apiBase}/proxy/stop`, {
                method: 'POST'
            });
        },
        
        // 重启代理
        restart: function() {
            return Utils.ajax(`${CONFIG.apiBase}/proxy/restart`, {
                method: 'POST'
            });
        },
        
        // 获取代理配置
        getConfig: function() {
            return Utils.ajax(`${CONFIG.apiBase}/proxy/config`);
        },
        
        // 更新代理配置
        updateConfig: function(config) {
            return Utils.ajax(`${CONFIG.apiBase}/proxy/config`, {
                method: 'POST',
                body: config
            });
        },
        
        // 获取代理日志
        getLogs: function(lines = 100) {
            return Utils.ajax(`${CONFIG.apiBase}/proxy/logs?lines=${lines}`);
        }
    };
    
    // 系统状态
    const System = {
        // 获取系统状态
        getStatus: function() {
            return Utils.ajax(`${CONFIG.apiBase}/system/status`);
        },
        
        // 获取系统信息
        getInfo: function() {
            return Utils.ajax(`${CONFIG.apiBase}/system/info`);
        },
        
        // 获取服务状态
        getServiceStatus: function() {
            return Utils.ajax(`${CONFIG.apiBase}/system/service`);
        },
        
        // 获取资源使用情况
        getResources: function() {
            return Utils.ajax(`${CONFIG.apiBase}/system/resources`);
        },
        
        // 获取网络状态
        getNetwork: function() {
            return Utils.ajax(`${CONFIG.apiBase}/system/network`);
        }
    };
    
    // 设置管理
    const Settings = {
        // 获取设置
        get: function(key) {
            return Utils.ajax(`${CONFIG.apiBase}/settings${key ? `?key=${key}` : ''}`);
        },
        
        // 更新设置
        update: function(key, value) {
            return Utils.ajax(`${CONFIG.apiBase}/settings`, {
                method: 'POST',
                body: key ? { [key]: value } : value
            });
        },
        
        // 重置设置
        reset: function() {
            return Utils.ajax(`${CONFIG.apiBase}/settings/reset`, {
                method: 'POST'
            });
        },
        
        // 备份设置
        backup: function() {
            return Utils.ajax(`${CONFIG.apiBase}/settings/backup`);
        },
        
        // 恢复设置
        restore: function(data) {
            return Utils.ajax(`${CONFIG.apiBase}/settings/restore`, {
                method: 'POST',
                body: data
            });
        }
    };
    
    // 初始化应用
    const init = function() {
        console.log('domain initialized');
        
        // 检查更新
        checkUpdates();
        
        // 初始化事件监听器
        initEventListeners();
        
        // 初始加载
        loadInitialData();
        
        // 设置自动刷新
        setAutoRefresh();
    };
    
    // 检查更新
    function checkUpdates() {
        Utils.ajax(`${CONFIG.apiBase}/system/check-update`)
            .then(data => {
                if (data.success && data.data.update_available) {
                    Utils.showNotification(
                        `New version ${data.data.latest_version} is available!`,
                        'info'
                    );
                }
            })
            .catch(() => {
                // 忽略错误
            });
    }
    
    // 初始化事件监听器
    function initEventListeners() {
        // 证书状态检查
        document.addEventListener('click', function(e) {
            if (e.target.matches('#checkCertStatus, .check-cert-status')) {
                e.preventDefault();
                checkCertificateStatus();
            }
            
            if (e.target.matches('#renewCertificate, .renew-certificate')) {
                e.preventDefault();
                renewCertificate();
            }
            
            if (e.target.matches('#generateCertificate, .generate-certificate')) {
                e.preventDefault();
                generateCertificate();
            }
            
            if (e.target.matches('#toggleProxy, .toggle-proxy')) {
                e.preventDefault();
                toggleProxy();
            }
        });
        
        // 表单提交
        document.addEventListener('submit', function(e) {
            if (e.target.matches('.domain-form')) {
                e.preventDefault();
                handleFormSubmit(e.target);
            }
        });
        
        // 标签切换
        document.addEventListener('click', function(e) {
            if (e.target.matches('.domain-tab')) {
                e.preventDefault();
                switchTab(e.target);
            }
        });
    }
    
    // 加载初始数据
    function loadInitialData() {
        // 加载系统状态
        System.getStatus().then(data => {
            if (data.success) {
                updateSystemStatus(data.data);
            }
        });
        
        // 加载证书状态
        Certificate.checkStatus().then(data => {
            updateCertificateStatus(data);
        }).catch(() => {
        // 忽略错误
        });
    }
    
    // 设置自动刷新
    function setAutoRefresh() {
        setInterval(() => {
            Certificate.checkStatus().then(data => {
                updateCertificateStatus(data);
            }).catch(() => {
                // 忽略错误
            });
        }, CONFIG.refreshInterval);
    }
    
    // 更新系统状态
    function updateSystemStatus(data) {
        // 更新系统状态显示
        const elements = document.querySelectorAll('.system-status');
        elements.forEach(el => {
            if (el.dataset.key && data[el.dataset.key]) {
                el.textContent = data[el.dataset.key];
            }
        });
    }
    
    // 更新证书状态
    function updateCertificateStatus(data) {
        // 更新证书状态显示
        const elements = document.querySelectorAll('.certificate-status');
        elements.forEach(el => {
            const status = data.status || 'unknown';
            const expiry = data.expiry;
            
            el.innerHTML = `
                <span class="certificate-status-dot certificate-status-dot-${status}"></span>
                <span>${getCertificateStatusText(status, expiry)}</span>
            `;
            
            // 添加过期警告
            if (status === 'valid' && expiry) {
                const expiryDate = new Date(expiry);
                const now = new Date();
                const daysLeft = Math.ceil((expiryDate - now) / (1000 * 60 * 60 * 24));
                
                if (daysLeft <= 30) {
                    el.classList.add('expiring');
                    if (daysLeft <= 7) {
                        el.classList.add('urgent');
                    }
                }
            }
        });
    }
    
    // 获取证书状态文本
    function getCertificateStatusText(status, expiry) {
        switch (status) {
            case 'valid':
                const expiryDate = new Date(expiry);
                const now = new Date();
                const daysLeft = Math.ceil((expiryDate - now) / (1000 * 60 * 60 * 24));
                
                if (daysLeft <= 0) {
                    return 'Expired';
                } else if (daysLeft <= 30) {
                    return `Expires in ${daysLeft} days`;
                } else {
                    return 'Valid';
                }
            case 'expired':
                return 'Expired';
            case 'expiring':
                return 'Expiring Soon';
            case 'none':
                return 'No Certificate';
            default:
                return 'Unknown';
        }
    }
    
    // 检查证书状态
    function checkCertificateStatus() {
        Utils.showLoading(document.querySelector('#certStatusContainer'));
        
        Certificate.checkStatus()
            .then(data => {
                updateCertificateStatus(data);
                Utils.showNotification('Certificate status checked successfully', 'success');
            })
            .catch(error => {
                Utils.showNotification(`Failed to check certificate status: ${error.message}`, 'error');
            });
    }
    
    // 续期证书
    function renewCertificate() {
        Utils.confirm('Are you sure you want to renew the certificate?')
            .then(confirmed => {
                if (confirmed) {
                    Utils.showLoading(document.querySelector('#certActions'));
                    
                    Certificate.renew()
                        .then(data => {
                            if (data.success) {
                                Utils.showNotification('Certificate renewal started successfully', 'success');
                                // 延迟后重新检查状态
                                setTimeout(checkCertificateStatus, 5000);
                            } else {
                                Utils.showNotification(`Failed to renew certificate: ${data.message}`, 'error');
                            }
                        })
                        .catch(error => {
                            Utils.showNotification(`Failed to renew certificate: ${error.message}`, 'error');
                        });
                }
            });
    }
    
    // 生成证书
    function generateCertificate() {
        const modal = Utils.createModal({
            title: 'Generate Certificate',
            content: `
                <form class="domain-form" id="generateCertForm">
                    <div class="domain-form-group">
                        <label class="domain-label" for="domain">Domain</label>
                        <input type="text" class="domain-input" id="domain" name="domain" required>
                        <div class="domain-help-text">Enter your domain name (e.g., example.com)</div>
                    </div>
                    
                    <div class="domain-form-group">
                        <label class="domain-label" for="email">Email</label>
                        <input type="email" class="domain-input" id="email" name="email" required>
                        <div class="domain-help-text">For certificate notifications</div>
                    </div>
                    
                    <div class="domain-form-group">
                        <label class="domain-checkbox">
                            <input type="checkbox" name="wildcard" id="wildcard">
                            <span>Wildcard Certificate</span>
                        </label>
                        <div class="domain-help-text">Include *.example.com subdomains</div>
                    </div>
                    
                    <div class="domain-form-group">
                        <label class="domain-checkbox">
                            <input type="checkbox" name="staging" id="staging">
                            <span>Use Staging Environment</span>
                        </label>
                        <div class="domain-help-text">For testing purposes only</div>
                    </div>
                </form>
            `,
            buttons: [
                {
                    text: 'Cancel',
                    type: 'secondary'
                },
                {
                    text: 'Generate',
                    type: 'primary',
                    onClick: () => {
                        const form = document.getElementById('generateCertForm');
                        const formData = new FormData(form);
                        const data = Object.fromEntries(formData.entries());
                        
                        Utils.showLoading(document.querySelector('#certActions'));
                        modal.close();
                        
                        Certificate.generate(data)
                            .then(result => {
                                if (result.success) {
                                    Utils.showNotification('Certificate generation started successfully', 'success');
                                    setTimeout(checkCertificateStatus, 5000);
                                } else {
                                    Utils.showNotification(`Failed to generate certificate: ${result.message}`, 'error');
                                }
                            })
                            .catch(error => {
                                Utils.showNotification(`Failed to generate certificate: ${error.message}`, 'error');
                            });
                    }
                }
            ]
        });
        
        modal.open();
    }
    
    // 切换代理
    function toggleProxy() {
        Proxy.getStatus()
            .then(data => {
                const isRunning = data.success && data.data.running;
                const action = isRunning ? Proxy.stop() : Proxy.start();
                
                return action.then(result => {
                    if (result.success) {
                        const newStatus = isRunning ? 'stopped' : 'started';
                        Utils.showNotification(`Proxy ${newStatus} successfully`, 'success');
                        
                        // 更新UI
                        const buttons = document.querySelectorAll('#toggleProxy, .toggle-proxy');
                        buttons.forEach(btn => {
                            btn.innerHTML = isRunning ? 
                                '<i class="icon icon-play"></i> Start Proxy' :
                                '<i class="icon icon-stop"></i> Stop Proxy';
                            btn.classList.toggle('domain-btn-secondary', !isRunning);
                            btn.classList.toggle('domain-btn-danger', isRunning);
                        });
                    } else {
                        Utils.showNotification(`Failed to ${isRunning ? 'stop' : 'start'} proxy: ${result.message}`, 'error');
                    }
                });
            })
            .catch(error => {
                Utils.showNotification(`Failed to get proxy status: ${error.message}`, 'error');
            });
    }
    
    // 处理表单提交
    function handleFormSubmit(form) {
        const formData = new FormData(form);
        const data = Object.fromEntries(formData.entries());
        const submitBtn = form.querySelector('button[type="submit"]');
        const originalText = submitBtn.innerHTML;
        
        // 显示加载状态
        submitBtn.disabled = true;
        submitBtn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> Saving...';
        
        // 确定API端点
        let endpoint = form.dataset.endpoint || 'settings';
        let method = 'POST';
        
        Utils.ajax(`${CONFIG.apiBase}/${endpoint}`, {
            method,
            body: data
        })
        .then(result => {
            if (result.success) {
                Utils.showNotification('Settings saved successfully', 'success');
                form.classList.add('saved');
                setTimeout(() => form.classList.remove('saved'), 3000);
            } else {
                Utils.showNotification(`Failed to save settings: ${result.message}`, 'error');
            }
        })
        .catch(error => {
            Utils.showNotification(`Failed to save settings: ${error.message}`, 'error');
        })
        .finally(() => {
            // 恢复按钮状态
            submitBtn.disabled = false;
            submitBtn.innerHTML = originalText;
        });
    }
    
    // 切换标签
    function switchTab(tab) {
        const tabContainer = tab.closest('.domain-tabs');
        const tabId = tab.dataset.tab;
        
        // 更新标签状态
        tabContainer.querySelectorAll('.domain-tab').forEach(t => {
            t.classList.remove('domain-tab-active');
        });
        tab.classList.add('domain-tab-active');
        
        // 显示对应内容
        const contentContainer = tabContainer.nextElementSibling;
        if (contentContainer && contentContainer.classList.contains('domain-tab-contents')) {
            contentContainer.querySelectorAll('.domain-tab-content').forEach(c => {
                c.classList.remove('domain-tab-content-active');
            });
            const activeContent = contentContainer.querySelector(`#${tabId}`);
            if (activeContent) {
                activeContent.classList.add('domain-tab-content-active');
            }
        }
    }
    
    // 公开API
    window.domain = {
        Utils,
        Certificate,
        DNS,
        Proxy,
        System,
        Settings,
        init,
        config: CONFIG
    };
    
    // 页面加载完成后初始化
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
