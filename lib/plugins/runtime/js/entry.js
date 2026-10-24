// Entry of the bundle: exposes node-html-parser's `parse` for the prelude,
// which captures it and removes the global before plugin code runs.
import { parse } from 'node-html-parser';

globalThis.__kartka_html_parse = parse;
