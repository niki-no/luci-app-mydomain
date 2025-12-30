/**
 * domain Enhanced JavaScript
 * Copyright (c) 2026 domain Maintainers
 * Licensed under the Apache License 2.0
 */

(function(domain) {
    'use strict';
    
    if (!window.domain) {
        console.error('domain core not found');
        return;
    }
    
    // 增强功能配置
    const ENHANCED_CONFIG = {
        realtimeUpdates: true,
        websocketEnabled: true,
        websocketUrl: 'ws://' + window.location.host + '/domain/ws',
        analytics: true,
        cacheTTL: 60000, // 1分钟
        offlineSupport: true
    };
    
    // 缓存管理
    const Cache = {
        storage: window.localStorage,
        prefix: 'domain_',
        
        set: function(key, value, ttl = ENHANCED_CONFIG.cacheTTL) {
            const item = {
                value: value,
                expiry: Date.now() + ttl
            };
            
            try {
                this.storage.setItem(this.prefix + key, JSON.stringify(item));
                return true;
            } catch (e) {
                console.warn('Cache set failed:', e);
                return false;
            }
        },
        
        get: function(key) {
            try {
                const itemStr = this.storage.getItem(this.prefix + key);
                if (!itemStr) return null;
                
                const item = JSON.parse(itemStr);
                if (Date.now() > item.expiry) {
                    this.remove(key);
                    return null;
                }
                
                return item.value;
            } catch (e) {
                console.warn('Cache get failed:', e);
                this.remove(key);
                return null;
            }
        },
        
        remove: function(key) {
            try {
                this.storage.removeItem(this.prefix + key);
            } catch (e) {
                console.warn('Cache remove failed:', e);
            }
        },
        
        clear: function() {
            try {
                for (let i = 0; i < this.storage.length; i++) {
                    const key = this.storage.key(i);
                    if (key.startsWith(this.prefix)) {
                        this.storage.removeItem(key);
                    }
                }
            } catch (e) {
                console.warn('Cache clear failed:', e);
            }
        }
    };
    
    // WebSocket管理器用于实时更新
    const WebSocketManager = {
        ws: null,
        reconnectAttempts: 0,
        maxReconnectAttempts: 5,
        reconnectDelay: 3000,
        listeners: new Map(),
        
        connect: function() {
            if (!ENHANCED_CONFIG.websocketEnabled) return;
            
            try {
                this.ws = new WebSocket(ENHANCED_CONFIG.websocketUrl);
                
                this.ws.onopen = () => {
                    console.log('domain WebSocket connected');
                    this.reconnectAttempts = 0;
                    this.notifyListeners('connected', {});
                    
                    // 订阅更新
                    this.send({
                        type: 'subscribe',
                        channels: ['certificate', 'proxy', 'dns', 'system']
                    });
                };
                
                this.ws.onmessage = (event) => {
                    try {
                        const data = JSON.parse(event.data);
                        this.handleMessage(data);
                    } catch (e) {
                        console.error('Failed to parse WebSocket message:', e);
                    }
                };
                
                this.ws.onclose = () => {
                    console.log('domain WebSocket disconnected');
                    this.notifyListeners('disconnected', {});
                    this.scheduleReconnect();
                };
                
                this.ws.onerror = (error) => {
                    console.error('domain WebSocket error:', error);
                    this.notifyListeners('error', { error });
                };
                
            } catch (e) {
                console.error('Failed to create WebSocket:', e);
                this.scheduleReconnect();
            }
        },
        
        disconnect: function() {
            if (this.ws) {
                this.ws.close();
                this.ws = null;
            }
        },
        
        send: function(data) {
            if (this.ws && this.ws.readyState === WebSocket.OPEN) {
                this.ws.send(JSON.stringify(data));
                return true;
            }
            return false;
        },
        
        scheduleReconnect: function() {
            if (this.reconnectAttempts < this.maxReconnectAttempts) {
                this.reconnectAttempts++;
                const delay = this.reconnectDelay * Math.pow(1.5, this.reconnectAttempts - 1);
                
                console.log(`Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})`);
                
                setTimeout(() => {
                    if (!this.ws || this.ws.readyState === WebSocket.CLOSED) {
                        this.connect();
                    }
                }, delay);
            } else {
                console.warn('Max reconnection attempts reached');
                this.notifyListeners('reconnect_failed', {});
            }
        },
        
        handleMessage: function(data) {
            const { type, channel, payload } = data;
            
            switch (type) {
                case 'update':
                    this.notifyListeners(channel, payload);
                    break;
                    
                case 'notification':
                    domain.Utils.showNotification(payload.message, payload.type || 'info');
                    break;
                    
                case 'error':
                    console.error('WebSocket error:', payload);
                    domain.Utils.showNotification(payload.message || 'WebSocket error', 'error');
                    break;
            }
        },
        
        addListener: function(channel, callback) {
            if (!this.listeners.has(channel)) {
                this.listeners.set(channel, new Set());
            }
            this.listeners.get(channel).add(callback);
            
            return () => this.removeListener(channel, callback);
        },
        
        removeListener: function(channel, callback) {
            if (this.listeners.has(channel)) {
                this.listeners.get(channel).delete(callback);
            }
        },
        
        notifyListeners: function(channel, data) {
            if (this.listeners.has(channel)) {
                this.listeners.get(channel).forEach(callback => {
                    try {
                        callback(data);
                    } catch (e) {
                        console.error('Listener error:', e);
                    }
                });
            }
        }
    };
    
    // 带有实时更新的增强型证书管理器
    const EnhancedCertificate = {
        ...domain.Certificate,
        
        checkStatus: function(domain) {
            const cacheKey = `cert_status_${domain || 'default'}`;
            const cached = Cache.get(cacheKey);
            
            if (cached) {
                return Promise.resolve(cached);
            }
            
            return domain.Certificate.checkStatus(domain)
                .then(data => {
                    Cache.set(cacheKey, data, 30000); // 30秒缓存
                    return data;
                });
        },
        
        renew: function(domain) {
            // 清除缓存
            Cache.remove(`cert_status_${domain || 'default'}`);
            
            return domain.Certificate.renew(domain)
                .then(data => {
                    // 通知WebSocket订阅者
                    WebSocketManager.send({
                        type: 'event',
                        channel: 'certificate',
                        event: 'renewed',
                        data: { domain, success: data.success }
                    });
                    
                    return data;
                });
        }
    };
    
    // 增强型DNS管理器
    const EnhancedDNS = {
        ...domain.DNS,
        
        getRecords: function(domain) {
            const cacheKey = `dns_records_${domain || 'all'}`;
            const cached = Cache.get(cacheKey);
            
            if (cached) {
                return Promise.resolve(cached);
            }
            
            return domain.DNS.getRecords(domain)
                .then(data => {
                    Cache.set(cacheKey, data, 60000); // 1分钟缓存
                    return data;
                });
        }
    };
    
    // 增强型代理管理器
    const EnhancedProxy = {
        ...domain.Proxy,
        
        getStatus: function() {
            const cacheKey = 'proxy_status';
            const cached = Cache.get(cacheKey);
            
            if (cached) {
                return Promise.resolve(cached);
            }
            
            return domain.Proxy.getStatus()
                .then(data => {
                    Cache.set(cacheKey, data, 10000); // 10秒缓存
                    return data;
                });
        },
        
        start: function() {
            Cache.remove('proxy_status');
            
            return domain.Proxy.start()
                .then(data => {
                    WebSocketManager.send({
                        type: 'event',
                        channel: 'proxy',
                        event: 'started',
                        data: { success: data.success }
                    });
                    
                    return data;
                });
        },
        
        stop: function() {
            Cache.remove('proxy_status');
            
            return domain.Proxy.stop()
                .then(data => {
                    WebSocketManager.send({
                        type: 'event',
                        channel: 'proxy',
                        event: 'stopped',
                        data: { success: data.success }
                    });
                    
                    return data;
                });
        }
    };
    
    // 数据分析管理器
    const Analytics = {
        enabled: ENHANCED_CONFIG.analytics,
        
        track: function(event, properties = {}) {
            if (!this.enabled) return;
            
            const data = {
                event,
                properties: {
                    ...properties,
                    timestamp: Date.now(),
                    userAgent: navigator.userAgent,
                    url: window.location.pathname
                }
            };
            
            // 发送到服务器
            fetch(domain.config.apiBase + '/analytics/track', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data)
            }).catch(() => {
                // 静默失败
            });
        },
        
        pageView: function(page) {
            this.track('page_view', { page });
        },
        
        buttonClick: function(buttonId) {
            this.track('button_click', { button_id: buttonId });
        },
        
        formSubmit: function(formId) {
            this.track('form_submit', { form_id: formId });
        },
        
        error: function(error, context = {}) {
            this.track('error', { error: error.toString(), ...context });
        }
    };
    
    // 性能监控
    const Performance = {
        metrics: new Map(),
        
        start: function(name) {
            this.metrics.set(name, {
                start: performance.now(),
                end: null,
                duration: null
            });
        },
        
        end: function(name) {
            const metric = this.metrics.get(name);
            if (metric && metric.start) {
                metric.end = performance.now();
                metric.duration = metric.end - metric.start;
                
                // 如果持续时间较长，则记录警告
                if (metric.duration > 1000) {
                    console.warn(`Performance: ${name} took ${metric.duration.toFixed(2)}ms`);
                }
                
                return metric.duration;
            }
            return null;
        },
        
        measure: function(name, fn) {
            this.start(name);
            const result = fn();
            
            if (result && typeof result.then === 'function') {
                return result.finally(() => this.end(name));
            } else {
                this.end(name);
                return result;
            }
        }
    };
    
    // 离线支持
    const OfflineSupport = {
        queue: [],
        isOnline: navigator.onLine,
        syncInterval: null,
        
        init: function() {
            if (!ENHANCED_CONFIG.offlineSupport) return;
            
            // 监听在线/离线事件
            window.addEventListener('online', this.handleOnline.bind(this));
            window.addEventListener('offline', this.handleOffline.bind(this));
            
            // 定期同步
            this.syncInterval = setInterval(this.syncQueue.bind(this), 60000); // 每分钟
            
            // 从存储加载队列
            this.loadQueue();
        },
        
        handleOnline: function() {
            this.isOnline = true;
            domain.Utils.showNotification('Back online - syncing changes', 'success');
            this.syncQueue();
        },
        
        handleOffline: function() {
            this.isOnline = false;
            domain.Utils.showNotification('You are offline - changes will be synced when back online', 'warning');
        },
        
        enqueue: function(action, data) {
            const item = {
                id: Date.now() + Math.random().toString(36).substr(2, 9),
                action,
                data,
                timestamp: Date.now(),
                retries: 0
            };
            
            this.queue.push(item);
            this.saveQueue();
            
            // 如果在线，立即尝试处理
            if (this.isOnline) {
                this.processQueue();
            }
            
            return item.id;
        },
        
        processQueue: function() {
            if (!this.isOnline || this.queue.length === 0) return;
            
            // 按顺序处理项目
            const item = this.queue[0];
            this.executeAction(item)
                .then(() => {
                    // 成功 - 从队列中移除
                    this.queue.shift();
                    this.saveQueue();
                    
                    // 处理下一个项目
                    if (this.queue.length > 0) {
                        setTimeout(() => this.processQueue(), 1000);
                    }
                })
                .catch(error => {
                    console.error('Failed to execute queued action:', error);
                    
                    // 增加重试次数
                    item.retries++;
                    
                    if (item.retries >= 3) {
                        // 重试次数过多 - 从队列中移除
                        console.warn('Action failed after 3 retries, removing from queue:', item);
                        this.queue.shift();
                        this.saveQueue();
                    } else {
                        // 延迟后重试
                        const delay = Math.min(30000, Math.pow(2, item.retries) * 1000); // 指数退避
                        setTimeout(() => this.processQueue(), delay);
                    }
                });
        },
        
        executeAction: function(item) {
            // 将操作映射到API调用
            switch (item.action) {
                case 'certificate.renew':
                    return domain.Certificate.renew(item.data.domain);
                    
                case 'dns.add_record':
                    return domain.DNS.addRecord(item.data.record);
                    
                case 'settings.update':
                    return domain.Settings.update(item.data.key, item.data.value);
                    
                default:
                    return Promise.reject(new Error(`Unknown action: ${item.action}`));
            }
        },
        
        syncQueue: function() {
            if (this.isOnline && this.queue.length > 0) {
                this.processQueue();
            }
        },
        
        saveQueue: function() {
            try {
                localStorage.setItem('domain_offline_queue', JSON.stringify(this.queue));
            } catch (e) {
                console.error('Failed to save offline queue:', e);
            }
        },
        
        loadQueue: function() {
            try {
                const saved = localStorage.getItem('domain_offline_queue');
                if (saved) {
                    this.queue = JSON.parse(saved);
                }
            } catch (e) {
                console.error('Failed to load offline queue:', e);
                this.queue = [];
            }
        },
        
        clearQueue: function() {
            this.queue = [];
            this.saveQueue();
        },
        
        getQueueLength: function() {
            return this.queue.length;
        }
    };
    
    // 增强型UI组件
    const EnhancedUI = {
        // 实时状态指示器
        createStatusIndicator: function(elementId, options = {}) {
            const element = document.getElementById(elementId);
            if (!element) return null;
            
            const indicator = document.createElement('div');
            indicator.className = 'status-indicator';
            
            const update = (status) => {
                indicator.className = `status-indicator status-${status}`;
                indicator.title = `Status: ${status}`;
            };
            
            // 初始状态
            update(options.initialStatus || 'unknown');
            
            element.appendChild(indicator);
            
            return {
                update,
                element: indicator
            };
        },
        
        // 自动刷新组件
        createAutoRefresh: function(elementId, refreshFn, interval = 30000) {
            const element = document.getElementById(elementId);
            if (!element) return null;
            
            let refreshInterval = null;
            let isRefreshing = false;
            
            const refreshButton = document.createElement('button');
            refreshButton.className = 'btn-refresh';
            refreshButton.innerHTML = '<i class="icon icon-refresh"></i>';
            refreshButton.addEventListener('click', manualRefresh);
            
            const statusSpan = document.createElement('span');
            statusSpan.className = 'refresh-status';
            statusSpan.textContent = 'Last updated: Just now';
            
            element.appendChild(refreshButton);
            element.appendChild(statusSpan);
            
            function manualRefresh() {
                if (!isRefreshing) {
                    performRefresh();
                }
            }
            
            function performRefresh() {
                if (isRefreshing) return;
                
                isRefreshing = true;
                refreshButton.classList.add('refreshing');
                refreshButton.innerHTML = '<i class="icon icon-spinner icon-spin"></i>';
                
                Promise.resolve(refreshFn())
                    .then(() => {
                        statusSpan.textContent = `Last updated: ${new Date().toLocaleTimeString()}`;
                    })
                    .catch(error => {
                        console.error('Auto-refresh failed:', error);
                    })
                    .finally(() => {
                        isRefreshing = false;
                        refreshButton.classList.remove('refreshing');
                        refreshButton.innerHTML = '<i class="icon icon-refresh"></i>';
                    });
            }
            
            function startAutoRefresh() {
                if (refreshInterval) clearInterval(refreshInterval);
                refreshInterval = setInterval(performRefresh, interval);
            }
            
            function stopAutoRefresh() {
                if (refreshInterval) {
                    clearInterval(refreshInterval);
                    refreshInterval = null;
                }
            }
            
            // 初始刷新
            setTimeout(performRefresh, 1000);
            
            // 启动自动刷新
            startAutoRefresh();
            
            return {
                manualRefresh,
                startAutoRefresh,
                stopAutoRefresh
            };
        },
        
        // 长操作进度条
        createProgressBar: function(elementId, options = {}) {
            const element = document.getElementById(elementId);
            if (!element) return null;
            
            const container = document.createElement('div');
            container.className = 'progress-container';
            
            const progressBar = document.createElement('div');
            progressBar.className = 'progress-bar';
            
            const progressText = document.createElement('div');
            progressText.className = 'progress-text';
            
            container.appendChild(progressBar);
            container.appendChild(progressText);
            element.appendChild(container);
            
            function update(progress, message) {
                const percentage = Math.min(100, Math.max(0, progress));
                progressBar.style.width = `${percentage}%`;
                progressText.textContent = message || `${Math.round(percentage)}%`;
                
                if (percentage >= 100) {
                    setTimeout(() => {
                        container.classList.add('completed');
                    }, 500);
                }
            }
            
            function complete(message) {
                update(100, message || 'Complete');
            }
            
            function reset() {
                update(0, 'Starting...');
                container.classList.remove('completed');
            }
            
            function remove() {
                container.remove();
            }
            
            // 初始状态
            reset();
            
            return {
                update,
                complete,
                reset,
                remove
            };
        }
    };
    
    // 初始化增强功能
    const initEnhanced = function() {
        console.log('domain Enhanced initialized');
        
        // 初始化离线支持
        if (ENHANCED_CONFIG.offlineSupport) {
            OfflineSupport.init();
        }
        
        // 连接WebSocket
        if (ENHANCED_CONFIG.websocketEnabled) {
            WebSocketManager.connect();
            
            // 设置实时监听器
            setupRealtimeListeners();
        }
        
        // 设置数据分析
        if (ENHANCED_CONFIG.analytics) {
            Analytics.pageView(window.location.pathname);
            
            // 跟踪按钮点击
            document.addEventListener('click', function(e) {
                const button = e.target.closest('button, .domain-btn, a.btn');
                if (button && button.id) {
                    Analytics.buttonClick(button.id);
                }
            });
            
            // 跟踪表单提交
            document.addEventListener('submit', function(e) {
                const form = e.target;
                if (form.id) {
                    Analytics.formSubmit(form.id);
                }
            });
        }
        
        // 为关键操作设置性能监控
        const originalCheckStatus = domain.Certificate.checkStatus;
        domain.Certificate.checkStatus = function(...args) {
            return Performance.measure('certificate.checkStatus', () => 
                originalCheckStatus.apply(this, args)
            );
        };
        
        // 将增强功能添加到domain对象
        domain.Enhanced = {
            Cache,
            WebSocketManager,
            Certificate: EnhancedCertificate,
            DNS: EnhancedDNS,
            Proxy: EnhancedProxy,
            Analytics,
            Performance,
            OfflineSupport,
            UI: EnhancedUI,
            config: ENHANCED_CONFIG
        };
    };
    
    // 设置实时监听器
    function setupRealtimeListeners() {
        // 证书更新
        WebSocketManager.addListener('certificate', (data) => {
            console.log('Certificate update received:', data);
            
            // 更新UI元素
            updateCertificateUI(data);
            
            // 对于重要更改显示通知
            if (data.event === 'expiring' || data.event === 'expired') {
                domain.Utils.showNotification(
                    `Certificate ${data.event}: ${data.domain}`,
                    data.event === 'expired' ? 'error' : 'warning'
                );
            }
        });
        
        // 代理更新
        WebSocketManager.addListener('proxy', (data) => {
            console.log('Proxy update received:', data);
            updateProxyUI(data);
        });
        
        // DNS更新
        WebSocketManager.addListener('dns', (data) => {
            console.log('DNS update received:', data);
            updateDNSUI(data);
        });
        
        // 系统更新
        WebSocketManager.addListener('system', (data) => {
            console.log('System update received:', data);
            updateSystemUI(data);
        });
    }
    
    // 根据实时数据更新证书UI
    function updateCertificateUI(data) {
        const elements = document.querySelectorAll('.certificate-status, .cert-info');
        
        elements.forEach(element => {
            if (data.domain && element.dataset.domain === data.domain) {
                updateCertificateElement(element, data);
            } else if (!element.dataset.domain) {
                updateCertificateElement(element, data);
            }
        });
    }
    
    function updateCertificateElement(element, data) {
        // 更新状态徽章
        const badge = element.querySelector('.status-badge');
        if (badge && data.status) {
            badge.className = `status-badge status-${data.status}`;
            badge.textContent = data.status.charAt(0).toUpperCase() + data.status.slice(1);
        }
        
        // 更新到期日期
        const expiryEl = element.querySelector('.cert-expiry');
        if (expiryEl && data.expiry) {
            expiryEl.textContent = domain.Utils.formatTime(data.expiry);
        }
        
        // 更新剩余天数
        const daysEl = element.querySelector('.cert-days');
        if (daysEl && data.expiry) {
            const expiryDate = new Date(data.expiry);
            const now = new Date();
            const daysLeft = Math.ceil((expiryDate - now) / (1000 * 60 * 60 * 24));
            daysEl.textContent = daysLeft > 0 ? `${daysLeft} days` : 'Expired';
            
            // 如果即将过期，添加警告类
            if (daysLeft <= 30) {
                daysEl.classList.add('warning');
            } else {
                daysEl.classList.remove('warning');
            }
        }
    }
    
    // 更新代理UI
    function updateProxyUI(data) {
        const statusEls = document.querySelectorAll('.proxy-status');
        
        statusEls.forEach(el => {
            if (data.status !== undefined) {
                el.textContent = data.status ? 'Running' : 'Stopped';
                el.className = `proxy-status status-${data.status ? 'running' : 'stopped'}`;
            }
        });
        
        // 更新切换按钮
        const toggleBtn = document.querySelector('#toggleProxy, .toggle-proxy');
        if (toggleBtn && data.status !== undefined) {
            toggleBtn.innerHTML = data.status ? 
                '<i class="icon icon-stop"></i> Stop Proxy' :
                '<i class="icon icon-play"></i> Start Proxy';
            toggleBtn.classList.toggle('domain-btn-danger', data.status);
            toggleBtn.classList.toggle('domain-btn-secondary', !data.status);
        }
    }
    
    // 更新DNS UI
    function updateDNSUI(data) {
        // 实现取决于具体的DNS UI结构
        console.log('DNS UI update:', data);
    }
    
    // 更新系统UI
    function updateSystemUI(data) {
        // 如果有可用数据，更新系统统计信息
        if (data.cpu !== undefined) {
            const cpuEls = document.querySelectorAll('.system-cpu');
            cpuEls.forEach(el => el.textContent = `${data.cpu}%`);
        }
        
        if (data.memory !== undefined) {
            const memEls = document.querySelectorAll('.system-memory');
            memEls.forEach(el => el.textContent = `${data.memory}%`);
        }
        
        if (data.uptime !== undefined) {
            const uptimeEls = document.querySelectorAll('.system-uptime');
            uptimeEls.forEach(el => el.textContent = formatUptime(data.uptime));
        }
    }
    
    function formatUptime(seconds) {
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        
        if (days > 0) return `${days}d ${hours}h`;
        if (hours > 0) return `${hours}h ${minutes}m`;
        return `${minutes}m`;
    }
    
    // 当domain核心准备就绪时初始化
    if (domain.config) {
        initEnhanced();
    } else {
        // 等待domain核心初始化
        const checkReady = setInterval(() => {
            if (domain.config) {
                clearInterval(checkReady);
                initEnhanced();
            }
        }, 100);
    }
    
})(window.domain || {});
