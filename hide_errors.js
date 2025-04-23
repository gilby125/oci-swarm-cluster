// ==UserScript==
// @name         Hide Cloudflare Dashboard Errors
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  Hide error messages in the Cloudflare dashboard without changing security settings
// @author       You
// @match        https://dash.cloudflare.com/*
// @grant        none
// ==/UserScript==

(function() {
    'use strict';
    
    // Override console.error to suppress specific error messages
    const originalConsoleError = console.error;
    console.error = function() {
        const errorMsg = arguments[0];
        if (typeof errorMsg === 'string' && 
            (errorMsg.includes('CORS') || 
             errorMsg.includes('Content-Security-Policy') || 
             errorMsg.includes('Adobe') || 
             errorMsg.includes('cookie not found') ||
             errorMsg.includes('edge.adobedc.net'))) {
            // Suppress these specific errors
            return;
        }
        return originalConsoleError.apply(this, arguments);
    };
    
    // Hide error banners that might appear at the bottom of the page
    function hideErrorBanners() {
        // Look for elements that might be error banners
        const errorSelectors = [
            '.error-banner',
            '.error-message',
            '.alert-error',
            '.alert-danger',
            '[role="alert"]',
            '.notification-error',
            '.error-notification',
            '.cf-error-banner',
            '.cf-error',
            '.cf-alert-error'
        ];
        
        errorSelectors.forEach(selector => {
            const elements = document.querySelectorAll(selector);
            elements.forEach(element => {
                // Check if it's an error element (contains error text or has red background)
                const computedStyle = window.getComputedStyle(element);
                const backgroundColor = computedStyle.backgroundColor;
                const text = element.textContent.toLowerCase();
                
                if (text.includes('error') || 
                    text.includes('failed') || 
                    backgroundColor.includes('rgb(220, 53, 69)') || // Red color
                    backgroundColor.includes('rgb(255, 0, 0)') ||
                    element.classList.contains('error')) {
                    element.style.display = 'none';
                }
            });
        });
    }
    
    // Run immediately and then periodically to catch dynamically added error banners
    hideErrorBanners();
    setInterval(hideErrorBanners, 1000);
    
    // Create a style element to hide error banners using CSS
    const style = document.createElement('style');
    style.textContent = `
        .error-banner, .error-message, .alert-error, .alert-danger, 
        [role="alert"], .notification-error, .error-notification,
        .cf-error-banner, .cf-error, .cf-alert-error {
            display: none !important;
        }
        
        /* Hide red banners at the bottom */
        div[style*="background-color: rgb(220, 53, 69)"],
        div[style*="background-color: rgb(255, 0, 0)"],
        div[style*="background-color: #dc3545"],
        div[style*="background-color: #ff0000"] {
            display: none !important;
        }
    `;
    document.head.appendChild(style);
})();
