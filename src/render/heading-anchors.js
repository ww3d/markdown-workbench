// --- Heading anchors (GitHub-compatible slugs) --------------------------------
//
// Give every heading an id derived from its visible text so in-document TOC
// links ([Text](#slug)) resolve in the preview (docs/DECISIONS.md #31). The
// slug rule follows github-slugger: lowercase, then strip every character that
// is not a Unicode letter, mark, decimal/letter number or connector
// punctuation, hyphen or space, then turn spaces into hyphens. Duplicate slugs
// get -1, -2, ... via the same occurrences bookkeeping github-slugger uses.
// github-slugger ships that set as a generated explicit character-class; this
// compact property-escape form matches it for the realistic cases but is not
// bitwise identical - it diverges only on obscure code points (Unicode
// assignments newer than github-slugger's pinned data, and 130 enclosed
// alphanumeric Latin letters in \p{So} - U+24B6..U+24E9 plus three blocks in
// U+1F130..U+1F189 - that github-slugger keeps). \p{Nd}\p{Nl}, NOT \p{N}: the
// latter also keeps \p{No} (m^2, fractions, circled digits) that github-slugger
// strips. See DECISIONS.md #31.
const SLUG_REMOVE = /[^\p{L}\p{M}\p{Nd}\p{Nl}\p{Pc}\- ]/gu;

function slugify(text) {
  return text.toLowerCase().replace(SLUG_REMOVE, '').replace(/ /g, '-');
}

// The visible text of a heading is the concatenated content of its inline
// text and code_inline children; markup tokens (emphasis, link delimiters)
// carry no content and do not contribute.
function headingText(inline) {
  let text = '';
  for (const child of inline.children || []) {
    if (child.type === 'text' || child.type === 'code_inline')
      text += child.content;
  }
  return text;
}

function headingAnchorsPlugin(md) {
  md.core.ruler.push('heading-anchors', (state) => {
    // Per-render occurrences map: the md instance is shared across renders, so
    // this state must live in the rule run, never at module scope, or the
    // duplicate suffix would leak between documents.
    const occurrences = Object.create(null);
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i].type !== 'heading_open') continue;
      const inline = tokens[i + 1];
      if (inline?.type !== 'inline') continue;
      const base = slugify(headingText(inline));
      let slug = base;
      while (slug in occurrences) {
        occurrences[base]++;
        slug = `${base}-${occurrences[base]}`;
      }
      occurrences[slug] = 0;
      tokens[i].attrSet('id', slug);
    }
    return true;
  });
}

module.exports = { headingAnchorsPlugin };
