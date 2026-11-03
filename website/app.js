// Same physical scale for the Mac and iPhone in the shared scene.
const phones = [...document.querySelectorAll('.phone-physical')];
function scalePhone(phone) {
  const sourceWidth = parseFloat(getComputedStyle(phone).getPropertyValue('--phone-source-width'));
  phone.style.setProperty('--phone-scale', phone.getBoundingClientRect().width / sourceWidth);
}
if ('ResizeObserver' in window) {
  const observer = new ResizeObserver(entries => entries.forEach(entry => scalePhone(entry.target)));
  phones.forEach(phone => observer.observe(phone));
} else {
  window.addEventListener('resize', () => phones.forEach(scalePhone));
}
phones.forEach(scalePhone);

const demoTabs = [...document.querySelectorAll('[data-demo-tab]')];
function selectTab(tab) {
  demoTabs.forEach(button => {
    const active = button === tab;
    button.setAttribute('aria-selected', String(active));
    button.tabIndex = active ? 0 : -1;
    document.getElementById(button.getAttribute('aria-controls')).hidden = !active;
  });
}
demoTabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectTab(tab));
  tab.addEventListener('keydown', event => {
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % demoTabs.length;
    else if (event.key === 'ArrowLeft') next = (index + demoTabs.length - 1) % demoTabs.length;
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = demoTabs.length - 1;
    else return;
    event.preventDefault();
    selectTab(demoTabs[next]);
    demoTabs[next].focus();
  });
});

// Null sources keep the honest placeholder. Add recordings in videos.json;
// browsers show native controls, never autoplay or make a fake play button.
async function loadVideos() {
  try {
    const response = await fetch('/videos.json');
    if (!response.ok) return;
    const videos = await response.json();
    document.querySelectorAll('[data-video-slot]').forEach(slot => {
      const entry = videos[slot.dataset.videoSlot];
      if (!entry?.src) return;
      const video = document.createElement('video');
      video.controls = true;
      video.playsInline = true;
      video.preload = 'metadata';
      video.setAttribute('aria-label', slot.querySelector('figcaption > span').textContent);
      if (entry.poster) video.poster = new URL(entry.poster, location.origin + '/').href;
      if (entry.captions) {
        const track = document.createElement('track');
        track.kind = 'captions';
        track.src = new URL(entry.captions, location.origin + '/').href;
        track.srclang = 'zh-CN';
        track.label = document.documentElement.lang.startsWith('zh') ? '简体中文' : 'Simplified Chinese';
        video.append(track);
      }
      // Preserve the placeholder when a configured recording is not available.
      const stage = slot.querySelector('.video-stage');
      const placeholder = [...stage.childNodes];
      video.addEventListener('error', () => {
        stage.replaceChildren(...placeholder);
        slot.classList.remove('has-video');
      }, { once: true });
      video.src = new URL(entry.src, location.origin + '/').href;
      stage.replaceChildren(video);
      slot.classList.add('has-video');
    });
  } catch {
    // Offline or missing configuration leaves the static demo previews intact.
  }
}
loadVideos();

// Social destinations can be filled in later without placeholder navigation.
document.querySelectorAll('[data-social-placeholder]').forEach(link => {
  const stayOnPage = event => event.preventDefault();
  link.addEventListener('click', stayOnPage);
  link.addEventListener('auxclick', stayOnPage);
});
