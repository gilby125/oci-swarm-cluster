// Content script to inject fixes into the page
const script = document.createElement('script');
script.src = chrome.runtime.getURL('js/inject.js');
(document.head || document.documentElement).appendChild(script);
script.onload = function() {
  script.remove();
};

// Intercept fetch requests to fix chat token
const originalFetch = window.fetch;
window.fetch = async function(url, options) {
  if (url.includes('/api/v4/user/chat/token')) {
    // Send message to background script to get a simulated token
    return new Promise((resolve) => {
      chrome.runtime.sendMessage({action: "fixChatToken"}, function(response) {
        resolve(new Response(JSON.stringify({
          success: true,
          result: {
            token: response.token
          }
        }), {
          status: 200,
          headers: {
            'Content-Type': 'application/json'
          }
        }));
      });
    });
  }
  return originalFetch.apply(this, arguments);
};
