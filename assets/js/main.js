(function() {
  "use strict";

  // Some people block Google Analytics (e.g. with AdBlock), so we need to check if it's working, or our links will
  // be broken.
  var isGoogleAnalyticsWorking = function() {
    return typeof ga == 'function' && ga.hasOwnProperty('loaded') && ga.loaded === true;
  };

  var trackOutboundLink = function(event) {
    if (!isGoogleAnalyticsWorking()) {
      return true;
    }

    var anchor = $(event.currentTarget);
    var url = anchor.attr('href');
    var trk = anchor.attr('data-trk');
    var target = anchor.attr('target');
    var valueString = anchor.attr('data-value');
    var value = valueString ? parseInt(valueString, 10) : 0;

    var props = {
      'hitType': 'event',
      'eventCategory': 'outbound',
      'eventAction': 'click-' + trk,
      'eventLabel': url,
      'eventValue': value
    };

    if (target !== "_blank") {
      event.preventDefault();
      props['hitCallback'] = function() {
        window.location = url;
      };
    }

    ga('send', props);
  };

  const trackLinksInGA = () => {
    $('.tracked').on('click', trackOutboundLink);
  };

  const handleReadMoreLinks = () => {
    for (const jsReadMoreLink of document.getElementsByClassName('js-read-more')) {
      jsReadMoreLink.addEventListener('click', (event) => {
        event.preventDefault();
        const elementId = jsReadMoreLink.dataset.target;
        const element = document.getElementById(elementId);
        element.classList.toggle('read-more');
        jsReadMoreLink.innerText = jsReadMoreLink.innerText === "(show)" ? "(hide)" : "(show)";
      });
    }
  };

  const enableAnchorJs = () => {
    anchors.add('h2');
  };

  const injectScriptTag = (src, attrs) => {
    const scriptTag = document.createElement('script');
    scriptTag.src = src;
    for (const [key, value] of Object.entries(attrs)) {
      scriptTag.setAttribute(key, value);
    }
    (document.head || document.body).appendChild(scriptTag);
  };

  const disqusBaseUrl = '//fundamentals-of-devops-and-software-delivery.disqus.com';

  const enableDisqus = () => {
    if (document.getElementById('disqus_thread')) {
      injectScriptTag(`${disqusBaseUrl}/embed.js`, {'data-timestamp': +new Date()});
    }
    injectScriptTag(`${disqusBaseUrl}/count.js`, {id: 'dsq-count-scr'});
  };

  const initialize = () => {
    trackLinksInGA();
    handleReadMoreLinks();
    enableAnchorJs();
    enableDisqus();
  };

  if (document.readyState !== 'loading') {
    initialize();
  } else {
    document.addEventListener('DOMContentLoaded', function(event) {
      initialize();
    });
  }
})();