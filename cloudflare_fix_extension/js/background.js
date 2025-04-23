// Background script to modify headers
chrome.webRequest.onHeadersReceived.addListener(
  function(details) {
    let responseHeaders = details.responseHeaders;
    
    // Remove existing CSP headers
    responseHeaders = responseHeaders.filter(header => 
      header.name.toLowerCase() !== 'content-security-policy' &&
      header.name.toLowerCase() !== 'content-security-policy-report-only'
    );
    
    // Add a more permissive CSP header
    responseHeaders.push({
      name: 'Content-Security-Policy',
      value: "default-src * 'unsafe-inline' 'unsafe-eval' data: blob:; script-src * 'unsafe-inline' 'unsafe-eval'; connect-src * 'unsafe-inline'; img-src * data: blob:; frame-src *; style-src * 'unsafe-inline';"
    });
    
    // Add CORS headers
    responseHeaders.push({
      name: 'Access-Control-Allow-Origin',
      value: '*'
    });
    
    responseHeaders.push({
      name: 'Access-Control-Allow-Methods',
      value: 'GET, POST, PUT, DELETE, OPTIONS'
    });
    
    responseHeaders.push({
      name: 'Access-Control-Allow-Headers',
      value: '*'
    });
    
    return { responseHeaders };
  },
  {
    urls: [
      "https://dash.cloudflare.com/*",
      "https://edge.adobedc.net/*",
      "https://*.cloudflare.com/*"
    ]
  },
  ["blocking", "responseHeaders"]
);

// Listen for messages from content script
chrome.runtime.onMessage.addListener(
  function(request, sender, sendResponse) {
    if (request.action === "fixChatToken") {
      // Simulate a successful chat token response
      sendResponse({success: true, token: "simulated_token_" + Date.now()});
    }
  }
);
