function parseBounds(bounds) {
  const match = /^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$/.exec(bounds ?? '');
  if (!match) {
    return null;
  }
  return match.slice(1).map(Number);
}

function getCenter(bounds) {
  const [x1, y1, x2, y2] = bounds;
  return {
    x: Math.trunc((x1 + x2) / 2),
    y: Math.trunc((y1 + y2) / 2),
  };
}

function getBrowserHomeSearchInputPoint(layout) {
  let best = null;

  function visit(node) {
    const attrs = node?.attributes ?? {};
    const nodeId = attrs.id || '';
    const bounds = parseBounds(attrs.bounds);

    if (bounds && nodeId === 'search_box_in_homepage') {
      const center = getCenter(bounds);
      const score = [center.y, center.x];
      if (!best || score.join(':') < best.score.join(':')) {
        best = {
          score,
          x: center.x,
          y: center.y,
        };
      }
    }

    for (const child of node?.children ?? []) {
      visit(child);
    }
  }

  visit(layout);
  return best ? { x: best.x, y: best.y } : null;
}

function getClickableAncestorBounds(ancestors = []) {
  const clickableAncestor = [...ancestors].reverse().find((ancestor) => {
    const ancestorAttrs = ancestor?.attributes ?? {};
    return (
      parseBounds(ancestorAttrs.bounds) &&
      (ancestorAttrs.clickable === 'true' ||
        ancestorAttrs.longClickable === 'true')
    );
  });
  return clickableAncestor
    ? parseBounds(clickableAncestor.attributes.bounds)
    : null;
}

function getUriCandidates(chromeUri) {
  const uri = chromeUri.trim().replace(/\/+$/, '');
  const host = uri.replace(/^https?:\/\//, '').replace(/\/+$/, '');
  return {
    uri,
    host,
    candidates: new Set([uri, `${uri}/`, host, `www.${host}`]),
  };
}

function getChromeUrlCandidateTapPoint(layout, chromeUri) {
  const { uri, host, candidates } = getUriCandidates(chromeUri);
  let best = null;

  function visit(node, ancestors = []) {
    const attrs = node?.attributes ?? {};
    const text = (attrs.text || attrs.originalText || '').trim();
    const nodeId = attrs.id || '';
    const bounds = parseBounds(attrs.bounds);

    if (
      bounds &&
      candidates.has(text) &&
      [
        'com.android.chrome:id/line_1',
        'com.android.chrome:id/line_2',
        'com.android.chrome:id/tile_view_title',
        'search_sug_item_content',
        'search_history_list_text',
        'search_url_text_in_search',
      ].includes(nodeId)
    ) {
      const tapBounds = getClickableAncestorBounds(ancestors) ?? bounds;
      const center = getCenter(tapBounds);
      const matchRank =
        text === uri ? 0 : text === host || text === `www.${host}` ? 1 : 2;
      const kindRank = {
        'com.android.chrome:id/line_2': 0,
        'com.android.chrome:id/line_1': 1,
        'com.android.chrome:id/tile_view_title': 2,
        search_sug_item_content: 0,
        search_history_list_text: 1,
        search_url_text_in_search: 2,
      }[nodeId];
      const score = [
        matchRank,
        kindRank,
        center.y,
        center.x,
      ];
      if (!best || score.join(':') < best.score.join(':')) {
        best = {
          score,
          x: center.x,
          y: center.y,
        };
      }
    }

    for (const child of node?.children ?? []) {
      visit(child, [...ancestors, node]);
    }
  }

  visit(layout);
  return best ? { x: best.x, y: best.y } : null;
}

function getSearchSubmitTapPoint(layout) {
  let best = null;

  function visit(node, ancestors = []) {
    const attrs = node?.attributes ?? {};
    const nodeId = attrs.id || '';
    const bounds = parseBounds(attrs.bounds);
    if (
      bounds &&
      ['search_btn_in_search'].includes(nodeId) &&
      (attrs.clickable === 'true' || attrs.longClickable === 'true')
    ) {
      const center = getCenter(bounds);
      const score = [center.y, center.x];
      if (!best || score.join(':') < best.score.join(':')) {
        best = { score, x: center.x, y: center.y };
      }
    }

    for (const child of node?.children ?? []) {
      visit(child, [...ancestors, node]);
    }
  }

  visit(layout);
  return best ? { x: best.x, y: best.y } : null;
}

function getSearchResultTapPoint(layout, chromeUri) {
  const { uri, host, candidates } = getUriCandidates(chromeUri);
  let best = null;

  function visit(node, ancestors = []) {
    const attrs = node?.attributes ?? {};
    const text = (attrs.text || attrs.originalText || '').trim();
    const nodeId = attrs.id || '';
    const bounds = parseBounds(attrs.bounds);

    if (
      bounds &&
      candidates.has(text) &&
      [
        'search_sug_item_content',
        'search_history_list_text',
        'search_url_text_in_search',
      ].includes(nodeId)
    ) {
      const tapBounds = getClickableAncestorBounds(ancestors) ?? bounds;
      const center = getCenter(tapBounds);
      const matchRank =
        text === uri || text === `${uri}/`
          ? 0
          : text === host || text === `www.${host}`
            ? 1
            : 2;
      const kindRank = {
        search_sug_item_content: 0,
        search_history_list_text: 1,
        search_url_text_in_search: 2,
      }[nodeId];
      const score = [matchRank, kindRank, center.y, center.x];
      if (!best || score.join(':') < best.score.join(':')) {
        best = { score, x: center.x, y: center.y };
      }
    }

    for (const child of node?.children ?? []) {
      visit(child, [...ancestors, node]);
    }
  }

  visit(layout);
  return best ? { x: best.x, y: best.y } : null;
}

export {
  getBrowserHomeSearchInputPoint,
  getChromeUrlCandidateTapPoint,
  getSearchResultTapPoint,
  getSearchSubmitTapPoint,
};

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  let mode = 'chrome-url-candidate';
  let layoutPath = args[0];
  let chromeUri = args[1];

  if (
    ['chrome-url-candidate', 'search-result', 'search-submit', 'browser-input']
      .includes(args[0])
  ) {
    mode = args[0];
    layoutPath = args[1];
    chromeUri = args[2];
  }

  if (!layoutPath || (mode !== 'search-submit' && mode !== 'browser-input' && !chromeUri)) {
    console.error(
      'usage: node scripts/ohos/chrome_layout.mjs [mode] <layout-json> [chrome-uri]',
    );
    process.exit(1);
  }

  const fs = await import('node:fs/promises');
  const layout = JSON.parse(await fs.readFile(layoutPath, 'utf8'));
  const point =
    mode === 'browser-input'
      ? getBrowserHomeSearchInputPoint(layout)
      : mode === 'search-submit'
        ? getSearchSubmitTapPoint(layout)
        : mode === 'search-result'
          ? getSearchResultTapPoint(layout, chromeUri)
          : getChromeUrlCandidateTapPoint(layout, chromeUri);
  if (!point) {
    process.exit(1);
  }
  console.log(`${point.x} ${point.y}`);
}
