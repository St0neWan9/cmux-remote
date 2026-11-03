// English is the default. Only an explicit choice (or a saved choice) changes it.
(() => {
  const storageKey = 'cmux-remote-language';
  const html = document.documentElement;
  const url = new URL(location.href);
  const normalize = value => value === 'zh' || value === 'zh-CN' ? 'zh' : value === 'en' ? 'en' : null;
  const save = language => { try { localStorage.setItem(storageKey, language); } catch {} };
  let saved;
  try { saved = normalize(localStorage.getItem(storageKey)); } catch {}
  const requested = normalize(url.searchParams.get('lang'));
  const pageLanguage = html.lang.startsWith('zh') ? 'zh' : 'en';
  const language = requested || (pageLanguage === 'zh' ? 'zh' : saved || 'en');
  if (requested || pageLanguage === 'zh') save(language);
  const routes = {
    home: { en: '/', zh: '/zh/' },
    system: { en: '/design-system.html', zh: '/zh/design-system.html' },
  };
  const page = html.dataset.page;
  if (routes[page] && language !== pageLanguage) {
    location.replace(routes[page][language] + url.search + url.hash);
    return;
  }
  document.addEventListener('DOMContentLoaded', () => {
    if (page === 'not-found') {
      // Translate in place so an unknown URL retains its real HTTP 404 status.
      const chinese = language === 'zh';
      html.lang = chinese ? 'zh-CN' : 'en';
      document.title = chinese ? '页面未找到 — Cmux Remote' : 'Page not found — Cmux Remote';
      const heading = document.querySelector('h1');
      heading.firstChild.textContent = chinese ? '这个页面，' : 'This page';
      heading.querySelector('span').textContent = chinese ? '还不在这里。' : "isn't here yet.";
      document.querySelector('main > p').textContent = chinese ? '回到首页，继续了解 Cmux Remote。' : 'Head back home to explore Cmux Remote.';
      const home = document.querySelector('main > a');
      home.textContent = chinese ? '返回首页 →' : 'Back home →';
      home.href = chinese ? '/zh/' : '/?lang=en';
      const toggle = document.querySelector('[data-language]');
      const next = chinese ? 'en' : 'zh';
      const target = new URL(location.href);
      target.searchParams.set('lang', next);
      toggle.href = target.pathname + target.search + target.hash;
      toggle.dataset.language = next;
      toggle.textContent = chinese ? 'EN' : '中文';
      toggle.lang = chinese ? 'en' : 'zh-CN';
      toggle.hreflang = toggle.lang;
      toggle.title = chinese ? '英文' : 'Simplified Chinese';
      toggle.setAttribute('aria-label', chinese ? '切换为英文' : 'Switch to Simplified Chinese');
    }
    // Native details keeps the language picker usable without JavaScript.
    const picker = document.querySelector('.language-menu');
    if (picker) {
      picker.querySelectorAll('[data-language]').forEach(link => {
        const params = new URLSearchParams(url.search);
        params.set('lang', link.dataset.language);
        link.href = routes[page][link.dataset.language] + '?' + params + url.hash;
        link.addEventListener('click', () => {
          const current = new URL(location.href);
          current.searchParams.set('lang', link.dataset.language);
          link.href = routes[page][link.dataset.language] + current.search + current.hash;
        });
      });
      document.addEventListener('click', event => {
        if (!picker.contains(event.target)) picker.open = false;
      });
      picker.addEventListener('keydown', event => {
        if (event.key === 'Escape' && picker.open) {
          picker.open = false;
          picker.querySelector('summary').focus();
        }
      });
    }
    document.querySelectorAll('[data-language]').forEach(link => {
      link.addEventListener('click', () => save(link.dataset.language));
    });
  });
})();
