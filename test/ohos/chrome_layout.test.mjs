import test from 'node:test';
import assert from 'node:assert/strict';
import {
  getBrowserHomeSearchInputPoint,
  getChromeUrlCandidateTapPoint,
} from '../../scripts/ohos/chrome_layout.mjs';

test('getChromeUrlCandidateTapPoint prefers the clickable omnibox suggestion row', () => {
  const layout = {
    attributes: {},
    children: [
      {
        attributes: {
          id: 'com.android.chrome:id/omnibox_suggestions_dropdown',
          bounds: '[0,338][1280,954]',
          clickable: 'false',
          longClickable: 'false',
        },
        children: [
          {
            attributes: {
              bounds: '[28,338][1252,534]',
              clickable: 'true',
              longClickable: 'true',
              type: 'android.view.ViewGroup',
            },
            children: [
              {
                attributes: {
                  id: 'com.android.chrome:id/line_1',
                  text: 'www.youtube.com',
                  bounds: '[224,365][1210,441]',
                  clickable: 'false',
                  longClickable: 'false',
                },
                children: [],
              },
              {
                attributes: {
                  id: 'com.android.chrome:id/line_2',
                  text: 'https://www.youtube.com',
                  bounds: '[224,441][1210,507]',
                  clickable: 'false',
                  longClickable: 'false',
                },
                children: [],
              },
            ],
          },
        ],
      },
    ],
  };

  assert.deepEqual(
    getChromeUrlCandidateTapPoint(layout, 'https://www.youtube.com'),
    { x: 640, y: 436 },
  );
});

test('getChromeUrlCandidateTapPoint falls back to a direct tile when no clickable ancestor exists', () => {
  const layout = {
    attributes: {},
    children: [
      {
        attributes: {
          id: 'com.android.chrome:id/tile_view_title',
          text: 'www.youtube.com',
          bounds: '[440,773][692,830]',
          clickable: 'false',
          longClickable: 'false',
        },
        children: [],
      },
    ],
  };

  assert.deepEqual(
    getChromeUrlCandidateTapPoint(layout, 'https://www.youtube.com'),
    { x: 566, y: 801 },
  );
});

test('getChromeUrlCandidateTapPoint resolves Harmony search suggestion rows via clickable ancestors', () => {
  const layout = {
    attributes: {},
    children: [
      {
        attributes: {
          id: 'searchPage',
          bounds: '[0,137][1280,1733]',
          clickable: 'false',
          longClickable: 'false',
        },
        children: [
          {
            attributes: {
              bounds: '[14,989][1266,1157]',
              clickable: 'true',
              longClickable: 'false',
              type: 'Row',
            },
            children: [
              {
                attributes: {
                  id: 'search_sug_item_content',
                  text: 'https://www.youtube.com',
                  bounds: '[154,1041][723,1106]',
                  clickable: 'false',
                  longClickable: 'false',
                },
                children: [],
              },
            ],
          },
          {
            attributes: {
              bounds: '[14,1158][1266,1326]',
              clickable: 'true',
              longClickable: 'false',
              type: 'Row',
            },
            children: [
              {
                attributes: {
                  id: 'search_sug_item_content',
                  text: 'https://www.youtube.com',
                  bounds: '[154,1210][723,1275]',
                  clickable: 'false',
                  longClickable: 'false',
                },
                children: [],
              },
            ],
          },
        ],
      },
    ],
  };

  assert.deepEqual(
    getChromeUrlCandidateTapPoint(layout, 'https://www.youtube.com'),
    { x: 640, y: 1073 },
  );
});

test('getBrowserHomeSearchInputPoint resolves the browser homepage search box center', () => {
  const layout = {
    attributes: {},
    children: [
      {
        attributes: {
          id: 'home_locationbar',
          bounds: '[56,137][1224,337]',
        },
        children: [
          {
            attributes: {
              id: 'search_box_in_homepage',
              bounds: '[153,169][913,304]',
            },
            children: [],
          },
        ],
      },
    ],
  };

  assert.deepEqual(getBrowserHomeSearchInputPoint(layout), { x: 533, y: 236 });
});
