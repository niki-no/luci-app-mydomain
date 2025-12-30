/**
 * domain Proxy Certificate JavaScript
 * Copyright (c) 2026 domain Maintainers
 * Licensed under the Apache License 2.0
 */

(function(domain) {
    'use strict';
    
    if (!window.domain) {
        console.error('domain core not found');
        return;
    }
    
    // Certificate Proxy Management
    const ProxyCertificate = {
        // Configuration
        config: {
            autoRenew: true,
            renewThreshold: 30, // days
            notificationDays: [60, 30, 14, 7, 3, 1],
            checkInterval: 3600000 // 1 hour
        },
        
        // Initialize
        init: function() {
            console.log('Proxy Certificate initialized');
            
            this.loadConfig();
            this.setupEventListeners();
            this.checkAllCertificates();
            
            // Set up periodic checks
            setInterval(() => this.checkAllCertificates(), this.config.checkInterval);
            
            // Set up WebSocket for real-time updates if available
            if (domain.Enhanced && domain.Enhanced.WebSocketManager) {
                this.setupWebSocket();
            }
        },
        
        // Load configuration
        loadConfig: function() {
            try {
                const saved = localStorage.getItem('domain_proxy_cert_config');
                if (saved) {
                    this.config = { ...this.config, ...JSON.parse(saved) };
                }
            } catch (e) {
                console.error('Failed to load proxy cert config:', e);
            }
        },
        
        // Save configuration
        saveConfig: function() {
            try {
                localStorage.setItem('domain_proxy_cert_config', JSON.stringify(this.config));
            } catch (e) {
                console.error('Failed to save proxy cert config:', e);
            }
        },
        
        // Setup event listeners
        setupEventListeners: function() {
            // Auto-renew toggle
            const autoRenewToggle = document.getElementById('autoRenewToggle');
            if (autoRenewToggle) {
                autoRenewToggle.checked = this.config.autoRenew;
                autoRenewToggle.addEventListener('change', (e) => {
                    this.config.autoRenew = e.target.checked;
                    this.saveConfig();
                    
                    domain.Utils.showNotification(
                        `Auto-renew ${e.target.checked ? 'enabled' : 'disabled'}`,
                        'success'
                    );
                });
            }
            
            // Renew threshold slider
            const renewThreshold = document.getElementById('renewThreshold');
            if (renewThreshold) {
                renewThreshold.value = this.config.renewThreshold;
                renewThreshold.addEventListener('input', (e) => {
                    this.config.renewThreshold = parseInt(e.target.value);
                    this.updateThresholdDisplay();
                });
                renewThreshold.addEventListener('change', () => {
                    this.saveConfig();
                    domain.Utils.showNotification('Renew threshold updated', 'success');
                });
                this.updateThresholdDisplay();
            }
            
            // Manual renew buttons
            document.addEventListener('click', (e) => {
                if (e.target.matches('.renew-certificate-btn, [data-action="renew-certificate"]')) {
                    e.preventDefault();
                    const domain = e.target.dataset.domain;
                    this.renewCertificate(domain);
                }
                
                if (e.target.matches('.view-certificate-btn, [data-action="view-certificate"]')) {
                    e.preventDefault();
                    const domain = e.target.dataset.domain;
                    this.viewCertificate(domain);
                }
                
                if (e.target.matches('.delete-certificate-btn, [data-action="delete-certificate"]')) {
                    e.preventDefault();
                    const domain = e.target.dataset.domain;
                    this.deleteCertificate(domain);
                }
            });
            
            // Bulk operations
            const bulkRenewBtn = document.getElementById('bulkRenew');
            if (bulkRenewBtn) {
                bulkRenewBtn.addEventListener('click', () => this.bulkRenew());
            }
            
            const bulkDeleteBtn = document.getElementById('bulkDelete');
            if (bulkDeleteBtn) {
                bulkDeleteBtn.addEventListener('click', () => this.bulkDelete());
            }
            
            // Check all certificates
            const checkAllBtn = document.getElementById('checkAllCertificates');
            if (checkAllBtn) {
                checkAllBtn.addEventListener('click', () => this.checkAllCertificates(true));
            }
            
            // Export certificates
            const exportBtn = document.getElementById('exportCertificates');
            if (exportBtn) {
                exportBtn.addEventListener('click', () => this.exportCertificates());
            }
            
            // Import certificates
            const importBtn = document.getElementById('importCertificates');
            if (importBtn) {
                importBtn.addEventListener('click', () => this.importCertificates());
            }
        },
        
        // Setup WebSocket for real-time updates
        setupWebSocket: function() {
            domain.Enhanced.WebSocketManager.addListener('certificate', (data) => {
                this.handleCertificateUpdate(data);
            });
        },
        
        // Update threshold display
        updateThresholdDisplay: function() {
            const display = document.getElementById('renewThresholdDisplay');
            if (display) {
                display.textContent = `${this.config.renewThreshold} days`;
            }
            
            const slider = document.getElementById('renewThreshold');
            if (slider) {
                const value = parseInt(slider.value);
                const min = parseInt(slider.min) || 1;
                const max = parseInt(slider.max) || 90;
                const percentage = ((value - min) / (max - min)) * 100;
                
                slider.style.background = `linear-gradient(to right, var(--primary) 0%, var(--primary) ${percentage}%, var(--border-color) ${percentage}%, var(--border-color) 100%)`;
            }
        },
        
        // Check all certificates
        checkAllCertificates: function(manual = false) {
            const container = document.getElementById('certificatesList');
            if (container) {
                if (manual) {
                    domain.Utils.showLoading(container);
                }
                
                domain.Certificate.list()
                    .then(response => {
                        if (response.success) {
                            this.displayCertificates(response.data.certificates);
                            this.scheduleRenewals(response.data.certificates);
                            
                            if (manual) {
                                domain.Utils.showNotification('Certificates checked successfully', 'success');
                            }
                        } else {
                            throw new Error(response.message);
                        }
                    })
                    .catch(error => {
                        console.error('Failed to check certificates:', error);
                        
                        if (manual) {
                            domain.Utils.showNotification(
                                `Failed to check certificates: ${error.message}`,
                                'error'
                            );
                        }
                    });
            }
        },
        
        // Display certificates in table
        displayCertificates: function(certificates) {
            const container = document.getElementById('certificatesList');
            if (!container) return;
            
            if (!certificates || certificates.length === 0) {
                container.innerHTML = `
                    <div class="domain-alert domain-alert-info">
                        <i class="icon icon-info"></i>
                        <div class="domain-alert-content">
                            No certificates found. <a href="#" onclick="domain.ProxyCertificate.generateCertificate()">Generate your first certificate</a>
                        </div>
                    </div>
                `;
                return;
            }
            
            let html = `
                <table class="domain-table">
                    <thead>
                        <tr>
                            <th><input type="checkbox" id="selectAllCerts"></th>
                            <th>Domain</th>
                            <th>Status</th>
                            <th>Expires</th>
                            <th>Days Left</th>
                            <th>Issuer</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
            `;
            
            certificates.forEach((cert, index) => {
                const statusClass = this.getStatusClass(cert);
                const statusText = this.getStatusText(cert);
                const daysLeft = this.getDaysLeft(cert.expiry);
                const isExpiringSoon = daysLeft <= this.config.renewThreshold;
                
                html += `
                    <tr class="${isExpiringSoon ? 'expiring-soon' : ''} ${daysLeft <= 0 ? 'expired' : ''}" data-domain="${cert.domain}">
                        <td><input type="checkbox" class="cert-checkbox" data-domain="${cert.domain}"></td>
                        <td>
                            <strong>${cert.domain}</strong>
                            ${cert.wildcard ? '<span class="domain-badge domain-badge-info">Wildcard</span>' : ''}
                            ${cert.staging ? '<span class="domain-badge domain-badge-warning">Staging</span>' : ''}
                        </td>
                        <td>
                            <span class="certificate-status">
                                <span class="certificate-status-dot ${statusClass}"></span>
                                ${statusText}
                            </span>
                        </td>
                        <td>${domain.Utils.formatTime(cert.expiry) || '-'}</td>
                        <td class="days-left ${daysLeft <= 7 ? 'warning' : ''}">${daysLeft > 0 ? daysLeft : 'Expired'}</td>
                        <td>${cert.issuer || '-'}</td>
                        <td class="actions">
                            <button class="domain-btn domain-btn-secondary view-certificate-btn" data-domain="${cert.domain}" title="View Details">
                                <i class="icon icon-eye"></i>
                            </button>
                            <button class="domain-btn domain-btn-primary renew-certificate-btn ${daysLeft > 30 ? 'hidden' : ''}" data-domain="${cert.domain}" title="Renew Certificate">
                                <i class="icon icon-refresh"></i>
                            </button>
                            <button class="domain-btn domain-btn-danger delete-certificate-btn" data-domain="${cert.domain}" title="Delete Certificate">
                                <i class="icon icon-trash"></i>
                            </button>
                        </td>
                    </tr>
                `;
            });
            
            html += `
                    </tbody>
                </table>
                
                <div class="table-footer">
                    <div class="bulk-actions">
                        <button class="domain-btn domain-btn-secondary" id="bulkRenew">
                            <i class="icon icon-refresh"></i> Renew Selected
                        </button>
                        <button class="domain-btn domain-btn-danger" id="bulkDelete">
                            <i class="icon icon-trash"></i> Delete Selected
                        </button>
                    </div>
                    <div class="table-summary">
                        Showing ${certificates.length} certificate${certificates.length !== 1 ? 's' : ''}
                    </div>
                </div>
            `;
            
            container.innerHTML = html;
            
            // Add event listeners for checkboxes
            const selectAll = document.getElementById('selectAllCerts');
            if (selectAll) {
                selectAll.addEventListener('change', (e) => {
                    const checkboxes = document.querySelectorAll('.cert-checkbox');
                    checkboxes.forEach(cb => cb.checked = e.target.checked);
                });
            }
            
            // Add hover effects
            const rows = container.querySelectorAll('tbody tr');
            rows.forEach(row => {
                row.addEventListener('mouseenter', () => {
                    const actions = row.querySelector('.actions');
                    if (actions) {
                        actions.style.opacity = '1';
                    }
                });
                
                row.addEventListener('mouseleave', () => {
                    const actions = row.querySelector('.actions');
                    if (actions) {
                        actions.style.opacity = '0.7';
                    }
                });
            });
        },
        
        // Get status class for certificate
        getStatusClass: function(cert) {
            if (!cert.status || cert.status === 'none') {
                return 'status-none';
            }
            
            if (cert.status === 'valid') {
                const daysLeft = this.getDaysLeft(cert.expiry);
                
                if (daysLeft <= 0) {
                    return 'status-expired';
                } else if (daysLeft <= 7) {
                    return 'status-critical';
                } else if (daysLeft <= 30) {
                    return 'status-warning';
                } else {
                    return 'status-valid';
                }
            }
            
            return 'status-invalid';
        },
        
        // Get status text for certificate
        getStatusText: function(cert) {
            if (!cert.status || cert.status === 'none') {
                return 'No Certificate';
            }
            
            if (cert.status === 'valid') {
                const daysLeft = this.getDaysLeft(cert.expiry);
                
                if (daysLeft <= 0) {
                    return 'Expired';
                } else if (daysLeft <= 7) {
                    return 'Critical';
                } else if (daysLeft <= 30) {
                    return 'Expiring Soon';
                } else {
                    return 'Valid';
                }
            }
            
            return 'Invalid';
        },
        
        // Get days left until expiry
        getDaysLeft: function(expiryDate) {
            if (!expiryDate) return -1;
            
            const expiry = new Date(expiryDate);
            const now = new Date();
            const diff = expiry - now;
            
            return Math.ceil(diff / (1000 * 60 * 60 * 24));
        },
        
        // Schedule renewals based on configuration
        scheduleRenewals: function(certificates) {
            if (!this.config.autoRenew) return;
            
            certificates.forEach(cert => {
                if (cert.status === 'valid') {
                    const daysLeft = this.getDaysLeft(cert.expiry);
                    
                    // Check if needs renewal
                    if (daysLeft <= this.config.renewThreshold && daysLeft > 0) {
                        console.log(`Scheduling renewal for ${cert.domain} (${daysLeft} days left)`);
                        
                        // Schedule renewal
                        this.scheduleCertificateRenewal(cert.domain, daysLeft);
                    }
                    
                    // Send notifications
                    this.sendNotifications(cert, daysLeft);
                }
            });
        },
        
        // Schedule a certificate renewal
        scheduleCertificateRenewal: function(domain, daysLeft) {
            // Calculate delay based on days left
            let delay = 0;
            
            if (daysLeft <= 1) {
                delay = 0; // Renew immediately
            } else if (daysLeft <= 7) {
                delay = 24 * 60 * 60 * 1000; // 1 day
            } else if (daysLeft <= 30) {
                delay = 7 * 24 * 60 * 60 * 1000; // 1 week
            } else {
                return; // Don't schedule if not expiring soon
            }
            
            // Schedule the renewal
            setTimeout(() => {
                this.renewCertificate(domain, true);
            }, delay);
        },
        
        // Send notifications for expiring certificates
        sendNotifications: function(cert, daysLeft) {
            // Check if we should send a notification
            if (this.config.notificationDays.includes(daysLeft)) {
                const message = `Certificate for ${cert.domain} expires in ${daysLeft} day${daysLeft !== 1 ? 's' : ''}`;
                const type = daysLeft <= 7 ? 'warning' : 'info';
                
                // Show browser notification if supported
                if ('Notification' in window && Notification.permission === 'granted') {
                    new Notification('Certificate Expiry', {
                        body: message,
                        icon: '/luci-static/resources/icons/certificate.png'
                    });
                }
                
                // Show in-app notification
                domain.Utils.showNotification(message, type);
                
                // Log to console
                console.log(`Certificate notification: ${message}`);
            }
        },
        
        // Handle certificate update from WebSocket
        handleCertificateUpdate: function(data) {
            console.log('Certificate update received:', data);
            
            // Update specific certificate in table
            const row = document.querySelector(`tr[data-domain="${data.domain}"]`);
            if (row) {
                this.updateCertificateRow(row, data);
            }
            
            // Show notification for important updates
            if (data.event === 'renewed') {
                domain.Utils.showNotification(
                    `Certificate renewed for ${data.domain}`,
                    'success'
                );
            } else if (data.event === 'expired') {
                domain.Utils.showNotification(
                    `Certificate expired for ${data.domain}`,
                    'error'
                );
            }
        },
        
        // Update certificate row in table
        updateCertificateRow: function(row, data) {
            // Update status
            const statusCell = row.querySelector('.certificate-status');
            if (statusCell) {
                const statusClass = this.getStatusClass(data);
                const statusText = this.getStatusText(data);
                
                statusCell.innerHTML = `
                    <span class="certificate-status-dot ${statusClass}"></span>
                    ${statusText}
                `;
            }
            
            // Update expiry date
            const expiryCell = row.querySelector('td:nth-child(4)');
            if (expiryCell && data.expiry) {
                expiryCell.textContent = domain.Utils.formatTime(data.expiry);
            }
            
            // Update days left
            const daysCell = row.querySelector('.days-left');
            if (daysCell) {
                const daysLeft = this.getDaysLeft(data.expiry);
                daysCell.textContent = daysLeft > 0 ? daysLeft : 'Expired';
                daysCell.className = `days-left ${daysLeft <= 7 ? 'warning' : ''}`;
            }
            
            // Update renew button visibility
            const renewBtn = row.querySelector('.renew-certificate-btn');
            if (renewBtn) {
                const daysLeft = this.getDaysLeft(data.expiry);
                renewBtn.classList.toggle('hidden', daysLeft > 30);
            }
            
            // Update row classes
            const daysLeft = this.getDaysLeft(data.expiry);
            row.classList.toggle('expiring-soon', daysLeft <= this.config.renewThreshold);
            row.classList.toggle('expired', daysLeft <= 0);
        },
        
        // Renew a certificate
        renewCertificate: function(domain, auto = false) {
            const confirmMessage = auto ? 
                `Auto-renewing certificate for ${domain}` :
                `Are you sure you want to renew the certificate for ${domain}?`;
            
            if (!auto) {
                domain.Utils.confirm(confirmMessage).then(confirmed => {
                    if (confirmed) {
                        this.performRenewal(domain);
                    }
                });
            } else {
                this.performRenewal(domain);
            }
        },
        
        // Perform the actual renewal
        performRenewal: function(domain) {
            // Show loading state
            const renewBtn = document.querySelector(`.renew-certificate-btn[data-domain="${domain}"]`);
            if (renewBtn) {
                const originalHTML = renewBtn.innerHTML;
                renewBtn.disabled = true;
                renewBtn.innerHTML = '<i class="icon icon-spinner icon-spin"></i>';
                
                domain.Certificate.renew(domain)
                    .then(response => {
                        if (response.success) {
                            domain.Utils.showNotification(
                                `Certificate renewal started for ${domain}`,
                                'success'
                            );
                            
                            // Update status after delay
                            setTimeout(() => {
                                this.checkCertificateStatus(domain);
                            }, 5000);
                        } else {
                            throw new Error(response.message);
                        }
                    })
                    .catch(error => {
                        domain.Utils.showNotification(
                            `Failed to renew certificate for ${domain}: ${error.message}`,
                            'error'
                        );
                    })
                    .finally(() => {
                        if (renewBtn) {
                            renewBtn.disabled = false;
                            renewBtn.innerHTML = originalHTML;
                        }
                    });
            }
        },
        
        // Check status of a specific certificate
        checkCertificateStatus: function(domain) {
            domain.Certificate.checkStatus(domain)
                .then(data => {
                    this.handleCertificateUpdate({
                        domain,
                        ...data
                    });
                })
                .catch(error => {
                    console.error(`Failed to check status for ${domain}:`, error);
                });
        },
        
        // View certificate details
        viewCertificate: function(domain) {
            domain.Certificate.checkStatus(domain)
                .then(data => {
                    this.showCertificateDetails(domain, data);
                })
                .catch(error => {
                    domain.Utils.showNotification(
                        `Failed to load certificate details: ${error.message}`,
                        'error'
                    );
                });
        },
        
        // Show certificate details modal
        showCertificateDetails: function(domain, data) {
            const details = data.details || {};
            
            const modal = domain.Utils.createModal({
                title: `Certificate Details: ${domain}`,
                content: `
                    <div class="certificate-details">
                        <div class="detail-section">
                            <h4>Basic Information</h4>
                            <div class="detail-grid">
                                <div class="detail-item">
                                    <span class="detail-label">Status:</span>
                                    <span class="detail-value">
                                        <span class="certificate-status">
                                            <span class="certificate-status-dot ${this.getStatusClass(data)}"></span>
                                            ${this.getStatusText(data)}
                                        </span>
                                    </span>
                                </div>
                                <div class="detail-item">
                                    <span class="detail-label">Expires:</span>
                                    <span class="detail-value">${domain.Utils.formatTime(data.expiry)}</span>
                                </div>
                                <div class="detail-item">
                                    <span class="detail-label">Days Left:</span>
                                    <span class="detail-value">${this.getDaysLeft(data.expiry)}</span>
                                </div>
                                <div class="detail-item">
                                    <span class="detail-label">Issuer:</span>
                                    <span class="detail-value">${data.issuer || '-'}</span>
                                </div>
                            </div>
                        </div>
                        
                        <div class="detail-section">
                            <h4>Certificate Details</h4>
                            <div class="detail-grid">
                                <div class="detail-item">
                                    <span class="detail-label">Serial Number:</span>
                                    <span class="detail-value">${details.serial || '-'}</span>
                                </div>
                                <div class="detail-item">
                                    <span class="detail-label">Algorithm:</span>
                                    <span class="detail-value">${details.algorithm || '-'}</span>
                                </div>
                                <div class="detail-item">
                                    <span class="detail-label">Key Size:</span>
                                    <span class="detail-value">${details.keySize || '-'}</span>
                                </div>
                                <div class="detail-item">
                                    <span class="detail-label">Signature Algorithm:</span>
                                    <span class="detail-value">${details.signatureAlgorithm || '-'}</span>
                                </div>
                            </div>
                        </div>
                        
                        <div class="detail-section">
                            <h4>Validity Period</h4>
                            <div class="detail-grid">
                                <div class="detail-item">
                                    <span class="detail-label">Not Before:</span>
                                    <span class="detail-value">${domain.Utils.formatTime(details.notBefore)}</span>
                                </div>
                                <div class="detail-item">
                                    <span class="detail-label">Not After:</span>
                                    <span class="detail-value">${domain.Utils.formatTime(details.notAfter)}</span>
                                </div>
                            </div>
                        </div>
                        
                        ${details.san ? `
                        <div class="detail-section">
                            <h4>Subject Alternative Names</h4>
                            <div class="san-list">
                                ${details.san.split(',').map(name => `<div class="san-item">${name.trim()}</div>`).join('')}
                            </div>
                        </div>
                        ` : ''}
                        
                        <div class="detail-section">
                            <h4>Certificate Chain</h4>
                            <div class="certificate-chain">
                                <pre>${details.chain || 'Not available'}</pre>
                            </div>
                        </div>
                    </div>
                `,
                buttons: [
                    {
                        text: 'Close',
                        type: 'secondary'
                    },
                    {
                        text: 'Renew Certificate',
                        type: 'primary',
                        onClick: () => {
                            modal.close();
                            this.renewCertificate(domain);
                        }
                    },
                    {
                        text: 'Download Certificate',
                        type: 'secondary',
                        onClick: () => {
                            this.downloadCertificate(domain);
                        }
                    }
                ]
            });
            
            modal.open();
        },
        
        // Download certificate
        downloadCertificate: function(domain) {
            const url = `${domain.config.apiBase}/cert/download?domain=${encodeURIComponent(domain)}`;
            window.open(url, '_blank');
        },
        
        // Delete a certificate
        deleteCertificate: function(domain) {
            domain.Utils.confirm(`Are you sure you want to delete the certificate for ${domain}? This action cannot be undone.`)
                .then(confirmed => {
                    if (confirmed) {
                        domain.Certificate.remove(domain)
                            .then(response => {
                                if (response.success) {
                                    domain.Utils.showNotification(
                                        `Certificate deleted for ${domain}`,
                                        'success'
                                    );
                                    
                                    // Remove from table
                                    const row = document.querySelector(`tr[data-domain="${domain}"]`);
                                    if (row) {
                                        row.remove();
                                    }
                                    
                                    // Update summary
                                    this.updateTableSummary();
                                } else {
                                    throw new Error(response.message);
                                }
                            })
                            .catch(error => {
                                domain.Utils.showNotification(
                                    `Failed to delete certificate: ${error.message}`,
                                    'error'
                                );
                            });
                    }
                });
        },
        
        // Bulk renew selected certificates
        bulkRenew: function() {
            const selected = this.getSelectedCertificates();
            
            if (selected.length === 0) {
                domain.Utils.showNotification('Please select certificates to renew', 'warning');
                return;
            }
            
            domain.Utils.confirm(`Renew ${selected.length} selected certificate${selected.length !== 1 ? 's' : ''}?`)
                .then(confirmed => {
                    if (confirmed) {
                        this.performBulkRenew(selected);
                    }
                });
        },
        
        // Perform bulk renew
        performBulkRenew: function(domains) {
            const progressBar = domain.Enhanced?.UI?.createProgressBar?.('certificatesList', {
                message: 'Renewing certificates...'
            });
            
            let completed = 0;
            const total = domains.length;
            
            domains.forEach((domain, index) => {
                setTimeout(() => {
                    domain.Certificate.renew(domain)
                        .then(() => {
                            completed++;
                            
                            if (progressBar) {
                                const progress = (completed / total) * 100;
                                progressBar.update(progress, `Renewed ${completed} of ${total}`);
                            }
                            
                            // Update this certificate
                            this.checkCertificateStatus(domain);
                            
                            // If all done
                            if (completed === total) {
                                if (progressBar) {
                                    progressBar.complete('All certificates renewed');
                                }
                                
                                domain.Utils.showNotification(
                                    `Successfully renewed ${total} certificate${total !== 1 ? 's' : ''}`,
                                    'success'
                                );
                            }
                        })
                        .catch(error => {
                            console.error(`Failed to renew ${domain}:`, error);
                            completed++;
                            
                            if (progressBar) {
                                const progress = (completed / total) * 100;
                                progressBar.update(progress, `Failed to renew ${domain}`);
                            }
                        });
                }, index * 2000); // Stagger requests
            });
        },
        
        // Bulk delete selected certificates
        bulkDelete: function() {
            const selected = this.getSelectedCertificates();
            
            if (selected.length === 0) {
                domain.Utils.showNotification('Please select certificates to delete', 'warning');
                return;
            }
            
            domain.Utils.confirm(`Delete ${selected.length} selected certificate${selected.length !== 1 ? 's' : ''}? This action cannot be undone.`)
                .then(confirmed => {
                    if (confirmed) {
                        this.performBulkDelete(selected);
                    }
                });
        },
        
        // Perform bulk delete
        performBulkDelete: function(domains) {
            domains.forEach(domain => {
                domain.Certificate.remove(domain)
                    .then(() => {
                        // Remove from table
                        const row = document.querySelector(`tr[data-domain="${domain}"]`);
                        if (row) {
                            row.remove();
                        }
                    })
                    .catch(error => {
                        console.error(`Failed to delete ${domain}:`, error);
                    });
            });
            
            // Update summary
            this.updateTableSummary();
            
            domain.Utils.showNotification(
                `Deleted ${domains.length} certificate${domains.length !== 1 ? 's' : ''}`,
                'success'
            );
        },
        
        // Get selected certificates
        getSelectedCertificates: function() {
            const checkboxes = document.querySelectorAll('.cert-checkbox:checked');
            const domains = [];
            
            checkboxes.forEach(cb => {
                if (cb.dataset.domain) {
                    domains.push(cb.dataset.domain);
                }
            });
            
            return domains;
        },
        
        // 更新表格摘要
        updateTableSummary: function() {
            const summary = document.querySelector('.table-summary');
            if (summary) {
                const rows = document.querySelectorAll('tbody tr');
                summary.textContent = `显示 ${rows.length} 个证书`;
            }
        },
        
        // 生成新证书
        generateCertificate: function() {
            // 这将打开证书生成表单
            window.location.href = '/cgi-bin/luci/admin/services/domain/certificate/generate';
        },
        
        // 导出证书
        exportCertificates: function() {
            domain.Certificate.list()
                .then(response => {
                    if (response.success) {
                        const data = JSON.stringify(response.data.certificates, null, 2);
                        const blob = new Blob([data], { type: 'application/json' });
                        const url = URL.createObjectURL(blob);
                        
                        const a = document.createElement('a');
                        a.href = url;
                        a.download = `domain-certificates-${new Date().toISOString().split('T')[0]}.json`;
                        document.body.appendChild(a);
                        a.click();
                        document.body.removeChild(a);
                        
                        URL.revokeObjectURL(url);
                        
                        domain.Utils.showNotification('证书导出成功', 'success');
                    } else {
                        throw new Error(response.message);
                    }
                })
                .catch(error => {
                    domain.Utils.showNotification(
                        `导出证书失败: ${error.message}`,
                        'error'
                    );
                });
        },
        
        // 导入证书
        importCertificates: function() {
            const input = document.createElement('input');
            input.type = 'file';
            input.accept = '.json';
            
            input.addEventListener('change', (e) => {
                const file = e.target.files[0];
                if (!file) return;
                
                const reader = new FileReader();
                reader.onload = (event) => {
                    try {
                        const data = JSON.parse(event.target.result);
                        console.log('导入证书:', data);
                        
                        // TODO: 实现导入逻辑
                        domain.Utils.showNotification(
                            '导入功能即将推出',
                            'info'
                        );
                    } catch (error) {
                        domain.Utils.showNotification(
                            '无效的证书文件',
                            'error'
                        );
                    }
                };
                
                reader.readAsText(file);
            });
            
            input.click();
        }
    };
    
    // 添加到domain对象
    domain.ProxyCertificate = ProxyCertificate;
    
    // 当domain准备就绪时初始化
    if (domain.config) {
        ProxyCertificate.init();
    } else {
        // 等待domain初始化
        const checkReady = setInterval(() => {
            if (domain.config) {
                clearInterval(checkReady);
                ProxyCertificate.init();
            }
        }, 100);
    }
    
})(window.domain || {});
