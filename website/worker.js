// Static assets answer every request with the whole file. Safari and iOS only play
// <video> sources that honor byte ranges, so media requests are sliced here; every
// other path is served by the asset binding directly (see run_worker_first).
export default {
  async fetch(request, env) {
    const response = await env.ASSETS.fetch(request);
    if (response.status !== 200 || !['GET', 'HEAD'].includes(request.method)) return response;
    const headers = new Headers(response.headers);
    headers.set('Accept-Ranges', 'bytes');
    const range = request.headers.get('Range');
    if (!range) return new Response(response.body, { status: 200, headers });

    const body = await response.arrayBuffer();
    const size = body.byteLength;
    const bounds = parseRange(range, size);
    if (!bounds) {
      headers.set('Content-Range', `bytes */${size}`);
      headers.delete('Content-Length');
      return new Response(null, { status: 416, headers });
    }
    const [start, end] = bounds;
    headers.set('Content-Range', `bytes ${start}-${end}/${size}`);
    headers.set('Content-Length', String(end - start + 1));
    return new Response(request.method === 'HEAD' ? null : body.slice(start, end + 1), { status: 206, headers });
  },
};

// One range only (what media players send); anything else is unsatisfiable.
export function parseRange(header, size) {
  const match = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!match || (match[1] === '' && match[2] === '') || size === 0) return null;
  if (match[1] === '') {
    const suffix = Number(match[2]);
    return suffix === 0 ? null : [Math.max(0, size - suffix), size - 1];
  }
  const start = Number(match[1]);
  const end = match[2] === '' ? size - 1 : Math.min(Number(match[2]), size - 1);
  return start < size && start <= end ? [start, end] : null;
}
